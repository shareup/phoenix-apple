import Foundation
import Combine

public typealias Payload = Dictionary<String, Any>

public final class Socket {
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

    private let _webSocket: WebSocketProtocol
    private var _channels: Dictionary<String, Channel> = [:]

    private let _ref = Ref.Generator()
    private let _pushTracker = PushTracker()
    
    private var _subscription: Subscription?

    private lazy var _synchronizationQueue: DispatchQueue = {
        let queue = DispatchQueue(label: "Phoenix.Socket._synchronizationQueue")
        queue.setSpecific(key: self._queueKey, value: self._queueContext)
        return queue
    }()
    private let _queueKey = DispatchSpecificKey<Int>()
    private lazy var _queueContext: Int = unsafeBitCast(self, to: Int.self)

    private var _timer: Timer?

    public init(websocket: WebSocketProtocol) {
        _webSocket = websocket
        
//        _webSocketSubscriber = _webSocket.subject.sink(receiveCompletion: { completion in
//            print("WebSocket publisher errored: \(completion)")
//            self.change(to: .closing)
//        }) { result in
//            switch result {
//            case .success(let message):
//                switch message {
//                case .string(let text):
//                    guard let data = text.data(using: .utf8) else { break }
//                    do {
//                        self.handle(incomingMessage: try IncomingMessage(data: data))
//                    } catch {
//                        print("Could not decode: '\(text)': \(error)")
//                    }
//                case .data:
//                    print("Don't support data frames at the moment")
//                @unknown default:
//                    fatalError()
//                }
//            case .failure(let error):
//                print("Error: \(error)")
//            }
//        }.eraseToAnySubscriber()
    }

    deinit {
        _timer?.invalidate()
    }
    
    private func track(_ topic: String) -> Channel {
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
    
    private func channel(for topic: String) -> Channel? {
        sync {
            if let _channel = _channels[topic] {
                return _channel
            } else {
                return nil
            }
        }
    }
    
    private func isTracked(_ topic: String) -> Bool {
        sync { return _channels.keys.contains(topic) }
    }
    
    public func join(_ topic: String) {
//        sync {
//            let channel: Channel = self.track(topic)
//
//            if isOpen && !channel.isJoining && !channel.isJoined {
//                push(channel.makeJoinPush())
//                channel.change(to: .joining)
//            }
//        }
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
//        sync {
//            guard isClosed else { return }
//            change(to: .connecting)
//            // _websocket.reopen()
//        }
    }

    public func disconnect() {
//        sync {
//            change(to: .closing)
//            _webSocket.close()
//        }
    }
}

extension Socket {
    private func flush() {
//        sync {
//            guard isOpen else { return }
//
//            _pushTracker.process { push -> OutgoingMessage? in
//                guard let channel = self.channel(for: push.topic) else { return nil }
//                guard let joinRef = channel.joinRef else { return nil }
//
//                let ref = _ref.advance()
//                let message = OutgoingMessage(joinRef: joinRef, ref: ref, push: push)
//                try? _webSocket.send(.data(message.encoded()), completionHandler: {_ in })
//                return message
//            }
//        }
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
                guard let joinRef = incomingMessage.joinRef else {
                    break
                }
                
                handleLeave(topic: message.topic, joinRef: joinRef)
            case .close:
                disconnect()
            case .error:
                // handle error
                fatalError()
            case .heartbeat:
                // handle heartbeat
                fatalError()
            case .reply:
                guard let joinRef = incomingMessage.joinRef else {
                    break
                }
                
                guard let ref = incomingMessage.ref,
                    let status = incomingMessage.payload["status"] as? String,
                    let response = incomingMessage.payload["response"] as? Payload,
                    let originalMessage = _pushTracker.find(related: incomingMessage) else {
                    handleCustom(message, joinRef: joinRef)
                    break
                }
                
                let reply = Reply(joinRef: joinRef, ref: ref, message: message, status: status, response: response)
                handleReply(reply, for: originalMessage.push)
            case .custom:
                guard let joinRef = incomingMessage.joinRef else {
                    break
                }
                
                handleCustom(message, joinRef: joinRef)
            }
            
            _pushTracker.cleanup(related: incomingMessage)
        }
    }
    
    private func handleJoin(topic: String, joinRef: Ref) {
//        sync {
//            guard let channel = self.channel(for: topic) else { return }
//            guard channel.isJoining else { return }
//
//            channel.change(to: .joined(joinRef))
//            _delegateQueue.async { [weak self] in self?.delegate?.didJoin(topic: topic) }
//        }
    }
    
    private func handleLeave(topic: String, joinRef: Ref) {
//        sync {
//            guard let channel = self.channel(for: topic) else { return }
//            guard channel.joinRef == joinRef else { return }
//
//            channel.change(to: .closed)
//            _delegateQueue.async { [weak self] in self?.delegate?.didLeave(topic: topic) }
//        }
    }
    
    private func handleReply(_ reply: Reply, for push: Push) {
//        sync {
//            if let callback = push.callback {
//                _delegateQueue.async { callback(reply) }
//            }
//
//            _delegateQueue.async { [weak self] in self?.delegate?.didReceive(reply: reply, from: push) }
//        }
    }
    
    private func handleCustom(_ message: Message, joinRef: Ref) {
//        sync {
//            guard let channel = channel(for: message.topic) else { return }
//            guard channel.joinRef == joinRef else { return }
//
//            _delegateQueue.async { [weak self] in self?.delegate?.didReceive(message: message) }
//        }
    }
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
    
    private func async(_ block: @escaping () -> Void) {
        _synchronizationQueue.async(execute: block)
    }
}

extension Socket {
    private func makeTimer() -> Timer {
        return Timer(timeInterval: 15, repeats: true) { [weak self] in self?.didFire(timer: $0) }
    }

    private func didFire(timer: Timer) {
//        sync {
//            switch _state {
//            case .closed:
//                async { self.connect() }
//            case .connecting, .closing:
//                break
//            case .open:
//                async { self.heartbeat() }
//            }
//        }
    }
}

//extension Socket: WebSocketDelegateProtocol {
//    public func didConnect(websocket: WebSocketProtocol) {
//        sync {
//            change(to: .open)
//            _channels.forEach { (_, channel) in
//                if !channel.isClosed {
//                    push(channel.makeJoinPush())
//                    channel.change(to: .joining)
//                }
//            }
//        }
//    }
//
//    public func didDisconnect(websocket: WebSocketProtocol, error: Error?) {
//        sync {
//            change(to: .closed)
//            _channels.forEach { (_, channel) in
//                // FIXME: this doesn't seem write at all
//                channel.change(to: .closed)
//                _delegateQueue.async { [weak self] in self?._delegate?.didLeave(topic: channel.topic) }
//            }
//        }
//    }
//
//    public func didReceiveMessage(websocket: WebSocketProtocol, text: String) {
//        guard let data = text.data(using: .utf8) else { return }
//
//        do {
//            handle(incomingMessage: try IncomingMessage(data: data))
//        } catch {
//            print("Could not decode: '\(text)': \(error)")
//        }
//    }
//
//    public func didReceiveData(websocket: WebSocketProtocol, data: Data) {
//        assertionFailure("\(#function) \(string(from: data))")
//    }
//}

private func string(from data: Data?) -> String {
    return String(describing: data.map({ String(data: $0, encoding: .utf8) }))
}
