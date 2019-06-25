import Foundation

public protocol SocketDelegate: class {
    func didJoin(topic: String)
    func didReceive(reply: Reply)
    func didReceive(message: Message)
    func didLeave(topic: String)
}

public typealias Payload = Dictionary<String, Any>

public final class Socket {
    private enum State {
        case disconnected
        case connecting
        case connected
    }

    public var delegate: SocketDelegate? {
        get { return sync { return self._delegate } }
        set { sync { self._delegate = newValue } }
    }

    public var autoReconnect: Bool = false {
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
    private var _channels: Dictionary<String, Channel> = [:]
    private weak var _delegate: SocketDelegate?
    private let _delegateQueue: DispatchQueue

    private var _state: State = .disconnected
    private let _ref = Ref.Generator()
    private let _pushTracker = PushTracker()

    private lazy var _synchronizationQueue: DispatchQueue = {
        let queue = DispatchQueue(label: "Phoenix.Socket._synchronizationQueue")
        queue.setSpecific(key: self._queueKey, value: self._queueContext)
        return queue
    }()
    private let _queueKey = DispatchSpecificKey<Int>()
    private lazy var _queueContext: Int = unsafeBitCast(self, to: Int.self)

    private var _timer: Timer?

    public init(websocket: WebSocketProtocol, delegate: SocketDelegate? = nil,
                delegateQueue: DispatchQueue = .main) {
        assert(websocket.delegate == nil)
        _websocket = websocket
        _delegate = delegate
        _delegateQueue = delegateQueue
        _websocket.callbackQueue = DispatchQueue(label: "Phoenix.Socket._websocket.callbackQueue")
        _websocket.delegate = self
    }

    deinit {
        _timer?.invalidate()
    }
    
    private func channel(for topic: String) -> Channel {
        sync {
            if let _channel = _channels[topic] {
                return _channel
            } else {
                let channel = Channel(topic: topic)
                _channels[topic] = channel
                return channel
            }
        }
    }
    
    public func join(_ topic: String) {
        let channel: Channel = self.channel(for: topic)
        push(channel.makeJoinPush())
    }

    public func push(topic: String, event: Event, payload: Dictionary<String, Any> = [:], callback: Push.Callback? = nil) {
        let push = Push(topic: topic, event: event, payload: payload, callback: callback)
        self.push(push)
        
    }
    
    public func push(_ push: Push) {
        _pushTracker.push(push)
        flush()
    }
}

extension Socket {
    public func connect() {
        sync {
            guard case .disconnected = _state else { return }
            _state = .connecting
            _websocket.connect()
        }
    }

    public func disconnect() {
        sync { _websocket.disconnect() }
    }
}

extension Socket {
    private func flush() {
        sync {
            guard case .connected = _state else { return }
            
            _pushTracker.process { push -> OutgoingMessage? in
                let channel = self.channel(for: push.topic)
                let ref = _ref.advance()
                
                guard let joinRef = channel.joinRef else { return nil }
                
                let message = OutgoingMessage(joinRef: joinRef, ref: ref, push: push)
                try? _websocket.write(data: message.encoded())
                return message
            }
        }
    }

    private func heartbeat() {
        push(Push(topic: "phoenix", event: .heartbeat))
    }
}

extension Socket {
    private func handle(incomingMessage: IncomingMessage) {
        sync {
            let message = Message(from: incomingMessage)
            
            switch message.event {
            case .join:
                guard let joinRef = incomingMessage.joinRef else { break }
                handleJoin(topic: message.topic, joinRef: joinRef)
            case .leave:
                handleLeave(topic: message.topic)
            case .close:
                disconnect()
            case .error:
                // handle error
                fatalError()
            case .heartbeat:
                // handle heartbeat
                fatalError()
            case .reply:
                guard let joinRef = incomingMessage.joinRef,
                    let ref = incomingMessage.ref,
                    let status = incomingMessage.payload["status"] as? String,
                    let response = incomingMessage.payload["response"] as? Payload,
                    let originalMessage = _pushTracker.find(related: incomingMessage) else {
                    handleCustom(message)
                    break
                }
                
                let reply = Reply(joinRef: joinRef, ref: ref, message: message, status: status, response: response)
                handleReply(reply, for: originalMessage)
            case .custom:
                handleCustom(message)
            }
            
            _pushTracker.cleanup(related: incomingMessage)
        }
    }
    
    private func handleJoin(topic: String, joinRef: Ref) {
        sync {
            let channel = self.channel(for: topic)
            
            if channel.joinRef == joinRef {
                channel.change(to: .joined(joinRef))
                _delegateQueue.async { [weak self] in self?.delegate?.didJoin(topic: topic) }
            }
        }
    }
    
    private func handleLeave(topic: String) {
        sync {
            let channel = self.channel(for: topic)
            channel.change(to: .disconnected)
            _delegateQueue.async { [weak self] in self?.delegate?.didLeave(topic: topic) }
        }
    }
    
    private func handleReply(_ reply: Reply, for originalMessage: OutgoingMessage) {
        sync {
            if let callback = originalMessage.push.callback {
                _delegateQueue.async { callback(reply) }
            }
            
            _delegateQueue.async { [weak self] in self?.delegate?.didReceive(reply: reply) }
        }
    }
    
    private func handleCustom(_ message: Message) {
        sync {
            _delegateQueue.async { [weak self] in self?.delegate?.didReceive(message: message) }
        }
    }

//    private func synced_handle(reply: Message, for push: Push) {
//        assert(isSynced)
//        switch (_state, push.event) {
//        case (_, .join):
//            synced_handleJoin(reply: reply, for: push)
//        case (.joined, .heartbeat):
//            synced_handleHeartbeat(reply: reply, for: push)
//        case (.joined, _):
//            _delegateQueue.async { [weak self] in self?.delegate?.didReceive(reply: reply, for: push) }
//        default:
//            break
//        }
//    }
//
//    private func synced_handleJoin(reply: Message, for push: Push) {
//        assert(isSynced)
//        if reply.isOk {
//            _state = .joined(push.ref)
//            let topic = _topic
//            _delegateQueue.async { [weak self] in self?.delegate?.didJoin(topic: topic) }
//            _pushTracker.removePush(for: push.ref)
//            synced_flushAllPushes()
//        } else {
//            _websocket.disconnect()
//        }
//    }
//
//    private func synced_handleHeartbeat(reply: Message, for push: Push) {
//        assert(isSynced)
//        if reply.isNotOk {
//            _websocket.disconnect()
//        }
//    }
}

extension Socket {
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

extension Socket {
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
        case .connected:
            heartbeat()
        }
    }
}

extension Socket: WebSocketDelegateProtocol {
    public func didConnect(websocket: WebSocketProtocol) {
        sync {
            _state = .connected
            _channels.forEach { (_, channel) in
                push(channel.makeJoinPush())
            }
        }
    }

    public func didDisconnect(websocket: WebSocketProtocol, error: Error?) {
        sync {
            _state = .disconnected
            _channels.forEach { (_, channel) in
                channel.change(to: .disconnected)
                _delegateQueue.async { [weak self] in self?._delegate?.didLeave(topic: channel.topic) }
            }
        }
    }

    public func didReceiveMessage(websocket: WebSocketProtocol, text: String) {
        guard let data = text.data(using: .utf8) else { return }

        do {
            handle(incomingMessage: try IncomingMessage(data: data))
        } catch {
            print("Could not decode: '\(text)': \(error)")
        }
    }

    public func didReceiveData(websocket: WebSocketProtocol, data: Data) {
        assertionFailure("\(#function) \(string(from: data))")
    }
}

private func string(from data: Data?) -> String {
    return String(describing: data.map({ String(data: $0, encoding: .utf8) }))
}
