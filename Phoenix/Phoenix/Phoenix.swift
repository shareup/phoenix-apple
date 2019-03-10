import Foundation

protocol PhoenixDelegate: class {
    func didJoin(topic: String)
    func didReceive(reply: Phoenix.Message, for: Phoenix.Push)
    func didReceive(message: Phoenix.Message)
    func didLeave(topic: String)
}

final class Phoenix {
    private enum State {
        case disconnected
        case connecting
        case joining
        case joined(Ref)
    }

    var delegate: PhoenixDelegate? {
        get { return sync { return self._delegate } }
        set { sync { self._delegate = newValue } }
    }

    var autoReconnect: Bool = false {
        didSet {
            sync {
                _timer?.invalidate()
                if autoReconnect {
                    let timer = makeTimer()
                    RunLoop.main.add(timer, forMode: .common)
                    _timer = timer
                }
            }
        }
    }

    private let _websocket: WebSocketProtocol
    private let _topic: String
    private weak var _delegate: PhoenixDelegate?
    private let _delegateQueue: DispatchQueue

    private var _state: State = .disconnected
    private let _ref = Ref.Generator()
    private let _pushTracker = PushTracker()

    private lazy var _synchronizationQueue: DispatchQueue = {
        let queue = DispatchQueue(label: "Phoenix._synchronizationQueue")
        queue.setSpecific(key: self._queueKey, value: self._queueContext)
        return queue
    }()
    private let _queueKey = DispatchSpecificKey<Int>()
    private lazy var _queueContext: Int = unsafeBitCast(self, to: Int.self)

    private var _timer: Timer?

    init(websocket: WebSocketProtocol, topic: String, delegate: PhoenixDelegate? = nil, delegateQueue: DispatchQueue = .main) {
        _websocket = websocket
        _topic = topic
        _delegate = delegate
        _delegateQueue = delegateQueue
        _websocket.callbackQueue = DispatchQueue(label: "Phoenix._websocket.callbackQueue")
        _websocket.delegate = self
    }

    deinit {
        _timer?.invalidate()
    }

    func push(event: Event, payload: Dictionary<String, Any> = [:]) {
        let push = Push(ref: _ref.advance(), topic: _topic, event: event, payload: payload)
        _pushTracker[push.ref] = push
        _synchronizationQueue.async { [weak self] in
            guard let self = self else { return }
            guard case .joined(let joinRef) = self._state else { return }
            self.synced_push(push, joinRef: joinRef)
        }
    }
}

extension Phoenix {
    func connect() {
        sync {
            guard case .disconnected = _state else { return }
            _state = .connecting
            _websocket.connect()
        }
    }

    func disconnect() {
        sync { _websocket.disconnect() }
    }
}

extension Phoenix {
    private func join(socket: WebSocketProtocol) {
        sync {
            let join = makeJoin()
            if let data = try? join.encoded() {
                _pushTracker[join.ref] = join
                _state = .joining
                socket.write(data: data)
            } else {
                socket.disconnect()
            }
        }
    }

    private func synced_flushAllPushes() {
        assert(isSynced)
        guard case .joined(let joinRef) = _state else { return }
        _pushTracker.allPushes.forEach { synced_push($0, joinRef: joinRef) }
    }

    private func synced_push(_ push: Push, joinRef: Ref) {
        assert(isSynced)
        do {
            _websocket.write(data: try push.encoded(with: joinRef))
        } catch {
            print("Could not encode \(String(describing: push))")
            _pushTracker.removePush(for: push.ref)
        }
    }

    private func heartbeat() {
        sync {
            guard case .joined(let ref) = _state else { return }
            let heartbeat = makeHeartbeat()
            guard let data = try? heartbeat.encoded(with: ref) else { return assertionFailure() }
            _pushTracker[heartbeat.ref] = heartbeat
            _websocket.write(data: data)
        }
    }

    private func makeJoin() -> Push {
        return Push(ref: _ref.advance(), topic: _topic, event: .join)
    }

    private func makeHeartbeat() -> Push {
        return Push(ref: _ref.advance(), topic: "phoenix", event: .heartbeat)
    }
}

extension Phoenix {
    private func handle(message: Message) {
        sync {
            if case .reply = message.event {
                if let ref = message.ref, let push = _pushTracker[ref] {
                    synced_handle(reply: message, for: push)
                    _pushTracker.removePush(for: ref)
                } else {
                    print("Missing Push for \(String(describing: message))")
                }
            } else if case .joined = _state {
                _delegateQueue.async { [weak self] in self?.delegate?.didReceive(message: message) }
            }
        }
    }

    private func synced_handle(reply: Message, for push: Push) {
        assert(isSynced)
        switch (_state, push.event) {
        case (_, .join):
            synced_handleJoin(reply: reply, for: push)
        case (.joined, .heartbeat):
            synced_handleHeartbeat(reply: reply, for: push)
        case (.joined, _):
            _delegateQueue.async { [weak self] in self?.delegate?.didReceive(reply: reply, for: push) }
        default:
            break
        }
    }

    private func synced_handleJoin(reply: Message, for push: Push) {
        assert(isSynced)
        if reply.isOk {
            _state = .joined(push.ref)
            let topic = _topic
            _delegateQueue.async { [weak self] in self?.delegate?.didJoin(topic: topic) }
            _pushTracker.removePush(for: push.ref)
            synced_flushAllPushes()
        } else {
            _websocket.disconnect()
        }
    }

    private func synced_handleHeartbeat(reply: Message, for push: Push) {
        assert(isSynced)
        if reply.isNotOk {
            _websocket.disconnect()
        }
    }
}

extension Phoenix {
    private func sync<T>(_ block: () throws -> T) rethrows -> T {
        if isSynced {
            return try block()
        } else {
            return try _synchronizationQueue.sync(execute: block)
        }
    }

    private func sync(_ block: () throws -> Void) rethrows {
        if isSynced {
            try block()
        } else {
            try _synchronizationQueue.sync(execute: block)
        }
    }

    private var isSynced: Bool {
        return DispatchQueue.getSpecific(key: _queueKey) == _queueContext
    }
}

extension Phoenix {
    private func makeTimer() -> Timer {
        return Timer(timeInterval: 15, repeats: true) { [weak self] in self?.didFire(timer: $0) }
    }

    private func didFire(timer: Timer) {
        let state: State = sync { return self._state }
        switch state {
        case .disconnected:
            connect()
        case .connecting:
            break
        case .joining:
            break
        case .joined:
            heartbeat()
        }
    }
}

extension Phoenix: WebSocketDelegateProtocol {
    func didConnect(websocket: WebSocketProtocol) {
        join(socket: websocket)
    }

    func didDisconnect(websocket: WebSocketProtocol, error: Error?) {
        sync {
            _state = .disconnected
            let topic = _topic
            _delegateQueue.async { [weak self] in self?._delegate?.didLeave(topic: topic) }
        }
    }

    func didReceiveMessage(websocket: WebSocketProtocol, text: String) {
        guard let data = text.data(using: .utf8) else { return }

        do {
            handle(message: try Message(data: data))
        } catch {
            print("Could not decode: '\(text)': \(error)")
        }
    }

    func didReceiveData(websocket: WebSocketProtocol, data: Data) {
        assertionFailure("\(#function) \(string(from: data))")
    }
}

private func string(from data: Data?) -> String {
    return String(describing: data.map({ String(data: $0, encoding: .utf8) }))
}

// TODO: Maybe add a timestamp to sent pushes so that we don't retry the same one
// multiple times in quick succession.
private final class PushTracker {
    private let _queue = DispatchQueue(label: "PushTracker._queue")
    private var _refToPush = Dictionary<Phoenix.Ref, Phoenix.Push>()

    var allPushes: Array<Phoenix.Push> {
        return _queue.sync {
            return _refToPush.sorted(by: { $0.0 < $1.0 }).map({ $0.value })
        }
    }

    subscript(ref: Phoenix.Ref) -> Phoenix.Push? {
        get { return _queue.sync { return _refToPush[ref] } }
        set { _queue.sync { _refToPush[ref] = newValue } }
    }

    @discardableResult
    func removePush(for ref: Phoenix.Ref) -> Phoenix.Push? {
        return _queue.sync { return _refToPush.removeValue(forKey: ref) }
    }
}
