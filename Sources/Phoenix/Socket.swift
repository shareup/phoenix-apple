import Combine
import Foundation
import Synchronized

private let backgroundQueue = DispatchQueue(label: "Socket.backgroundQueue")

public final class Socket {
    public typealias Output = Socket.Message
    public typealias Failure = Never

    public typealias ReconnectTimeInterval = (Int) -> DispatchTimeInterval

    private let lock: RecursiveLock = RecursiveLock()
    private func sync<T>(_ block: () throws -> T) rethrows -> T { return try lock.locked(block) }
    
    private let subject = PassthroughSubject<Output, Failure>()
    private var state: State = .closed
    private var shouldReconnect = true
    private var webSocketSubscriber: AnyCancellable?
    private var channels = [Topic: WeakChannel]()
    
    public var joinedChannels: [Channel] {
        let channels = sync { self.channels }
        return channels.compactMap { $0.value.channel }
    }

    private var pending: [Push] = []
    var pendingPushes: [Push] { sync { return pending } } // For testing

    public let url: URL
    public let timeout: DispatchTimeInterval

    private let notifySubjectQueue = DispatchQueue(label: "Socket.notifySubjectQueue")

    private let refGenerator: Ref.Generator

    var currentRef: Ref { refGenerator.current }
    func advanceRef() -> Ref { refGenerator.advance() }

    private let heartbeatPush = Push(topic: "phoenix", event: .heartbeat)
    private var pendingHeartbeatRef: Ref? = nil
    private var heartbeatTimer: Timer? = nil

    public static let defaultTimeout: DispatchTimeInterval = .seconds(10)
    public static let defaultHeartbeatInterval: DispatchTimeInterval = .seconds(30)
    public let heartbeatInterval: DispatchTimeInterval

    // https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/js/phoenix.js#L790
    public var reconnectTimeInterval: ReconnectTimeInterval = { (attempt: Int) -> DispatchTimeInterval in
        let milliseconds = [10, 50, 100, 150, 200, 250, 500, 1000, 2000, 5000]
        switch attempt {
        case 0:
            assertionFailure("`attempt` should start at 1")
            return .milliseconds(milliseconds[5])
        case (1..<milliseconds.count):
            return .milliseconds(milliseconds[attempt - 1])
        default:
            return .milliseconds(milliseconds[milliseconds.count - 1])
        }
    }
    private var _reconnectAttempts: Int = 0
    var reconnectAttempts: Int {
        get { sync { _reconnectAttempts } }
        set { sync { _reconnectAttempts = newValue } }
    }
    
    var isClosed: Bool { sync {
        guard case .closed = state else { return false }
        return true
    } }
    
    var isConnecting: Bool { sync {
        guard case .connecting = state else { return false }
        return true
    } }
    
    var isOpen: Bool { sync {
        guard case .open = state else { return false }
        return true
    } }
    
    var isClosing: Bool { sync {
        guard case .closing = state else { return false }
        return true
    } }
    
    var connectionState: String { sync {
        switch state {
        case .closed:
            return "closed"
        case .connecting:
            return "connecting"
        case .open:
            return "open"
        case .closing:
            return "closing"
        }
    } }
    
    public init(url: URL,
                timeout: DispatchTimeInterval = Socket.defaultTimeout,
                heartbeatInterval: DispatchTimeInterval = Socket.defaultHeartbeatInterval) {
        self.timeout = timeout
        self.heartbeatInterval = heartbeatInterval
        self.refGenerator = Ref.Generator()
        self.url = Socket.webSocketURLV2(url: url)
    }
    
    init(url: URL,
         timeout: DispatchTimeInterval = Socket.defaultTimeout,
         heartbeatInterval: DispatchTimeInterval = Socket.defaultHeartbeatInterval,
         refGenerator: Ref.Generator) {
        self.timeout = timeout
        self.heartbeatInterval = heartbeatInterval
        self.refGenerator = refGenerator
        self.url = Socket.webSocketURLV2(url: url)
    }

    deinit {
        sync {
            shouldReconnect = false
            cancelHeartbeatTimer()
            state.webSocket?.close()
            state = .closed
        }
    }
}

// MARK: Phoenix socket URL

extension Socket {
    static func webSocketURLV2(url original: URL) -> URL {
        return original
            .appendingPathComponent("websocket")
            .appendingQueryItems(["vsn": "2.0.0"])
    }
}

// MARK: Publisher

extension Socket: Publisher {
    public func receive<S>(subscriber: S)
        where S: Combine.Subscriber, Failure == S.Failure, Output == S.Input {
            subject.receive(subscriber: subscriber)
    }
}

// MARK: ConnectablePublisher

extension Socket: ConnectablePublisher {
    private struct Canceller: Cancellable {
        weak var socket: Socket?
        
        func cancel() {
            socket?.disconnect()
        }
    }

    @discardableResult public func connect() -> Cancellable {
        sync {
            self.shouldReconnect = true
            
            switch state {
            case .closed:
                let ws = WebSocket(url: url)
                self.state = .connecting(ws)

                let subject = self.subject
                notifySubjectQueue.async { subject.send(.connecting) }
                
                self.webSocketSubscriber = makeWebSocketSubscriber(with: ws)
                cancelHeartbeatTimer()
                createHeartbeatTimer()
                
                return Canceller(socket: self)
            case .connecting, .open:
                // NOOP
                return Canceller(socket: self)
            case .closing:
                // let the reconnect logic handle this case
                return Canceller(socket: self)
            }
        }
    }
    
    public func disconnect() {
        sync {
            self.shouldReconnect = false
            
            self.cancelHeartbeatTimer()
            
            switch state {
            case .closed, .closing:
                // NOOP
                return
            case .open(let ws), .connecting(let ws):
                self.state = .closing(ws)

                let subject = self.subject
                notifySubjectQueue.async { subject.send(.closing) }

                ws.close()
            }
        }
    }
}

// MARK: Channel

extension Socket {
    public func join(_ channel: Channel) {
        return channel.join()
    }

    public func join(_ topic: Topic, payload: Payload = [:]) -> Channel {
        sync {
            let _channel = channel(topic, payload: payload)
            _channel.join()
            return _channel
        }
    }
    
    public func channel(_ topic: Topic, payload: Payload = [:]) -> Channel {
        sync {
            if let weakChannel = channels[topic],
                let _channel = weakChannel.channel {
                return _channel
            }
            
            let _channel = Channel(topic: topic, joinPayload: payload, socket: self)
            
            channels[topic] = WeakChannel(_channel)
            
            return _channel
        }
    }

    public func leave(_ channel: Channel) {
        leave(channel.topic)
    }

    public func leave(_ topic: Topic) {
        removeChannel(for: topic)?.leave()
    }

    @discardableResult
    private func removeChannel(for topic: Topic) -> Channel? {
        return sync {
            guard let weakChannel = self.channels[topic], let channel = weakChannel.channel else { return nil }
            self.channels.removeValue(forKey: topic)
            return channel
        }
    }
}

// MARK: Push event

extension Socket {
    public func push(topic: Topic, event: PhxEvent) {
        push(topic: topic, event: event, payload: [:])
    }
    
    public func push(topic: Topic, event: PhxEvent, payload: Payload) {
        push(topic: topic, event: event, payload: payload) { _ in }
    }
    
    public func push(topic: Topic,
                     event: PhxEvent,
                     payload: Payload = [:],
                     callback: @escaping Callback) {
        let thePush = Socket.Push(
            topic: topic,
            event: event,
            payload: payload,
            callback: callback
        )
        
        sync {
            pending.append(thePush)
        }

        self.flushAsync()
    }
}

// MARK: Flush

extension Socket {
    private func flush() {
        sync {
            guard case .open = state else { return }

            guard let push = pending.first else { return }
            self.pending = Array(self.pending.dropFirst())
            
            let ref = advanceRef()
            let message = OutgoingMessage(push, ref: ref)
            
            send(message) { error in
                if error == nil {
                    self.flushAsync()
                }
                push.asyncCallback(error)
            }
        }
    }
    
    private func flushAsync() {
        backgroundQueue.async { self.flush() }
    }
}

// MARK: Send

extension Socket {
    func send(_ message: OutgoingMessage) {
        send(message, completionHandler: { _ in })
    }
    
    func send(_ message: OutgoingMessage, completionHandler: @escaping Callback) {
        Swift.print("socket sending", message)
        
        do {
            let data = try message.encoded()
            send(data, completionHandler: completionHandler)
        } catch {
            completionHandler(Error.couldNotSerializeOutgoingMessage(message))
        }
    }
    
    func send(_ string: String) {
        send(string) { _ in }
    }
    
    func send(_ string: String, completionHandler: @escaping Callback) {
        Swift.print("socket sending string", string)
        
        sync {
            switch state {
            case .open(let ws):
                // TODO: capture obj-c exceptions over in the WebSocket class
                ws.send(string) { error in
                    if let error = error {
                        Swift.print("Error writing to WebSocket: \(error)")
                        self.state = .closing(ws) // TODO: write a test to prove this works
                        ws.close(.abnormalClosure)
                    }
                    
                    completionHandler(error)
                }
            default:
                completionHandler(Socket.Error.notOpen)
            }
        }
    }
    
    func send(_ data: Data) {
        send(data, completionHandler: { _ in })
    }
    
    func send(_ data: Data, completionHandler: @escaping Callback) {
        Swift.print("socket sending data", String(describing: data))
        
        sync {
            switch state {
            case .open(let ws):
                // TODO: capture obj-c exceptions over in the WebSocket class
                ws.send(data) { error in
                    if let error = error {
                        Swift.print("Error writing to WebSocket: \(error)")
                        self.state = .closing(ws) // TODO: write a test to prove this works
                        ws.close(.abnormalClosure)
                    }
                    
                    completionHandler(error)
                }
            default:
                completionHandler(Socket.Error.notOpen)
                
                let subject = self.subject
                notifySubjectQueue.async { subject.send(.close) }
            }
        }
    }
}
    
// MARK: Heartbeat

extension Socket {
    typealias HeartbeatSuccessHandler = () -> Void

    func sendHeartbeat(_ onSuccess: HeartbeatSuccessHandler? = nil) {
        let msg: OutgoingMessage? = sync {
            guard pendingHeartbeatRef == nil else {
                heartbeatTimeout()
                return nil
            }
            
            guard case .open = state else { return nil }

            let pendingHeartbeatRef = advanceRef()
            self.pendingHeartbeatRef = pendingHeartbeatRef
            return OutgoingMessage(heartbeatPush, ref: pendingHeartbeatRef)
        }

        guard let message = msg else { return }
            
        Swift.print("writing heartbeat")

        send(message) { error in
            if let error = error {
                Swift.print("error writing heartbeat push", error)
                self.heartbeatTimeout()
            } else if let onSuccess = onSuccess {
                onSuccess()
            }
        }
    }
    
    func heartbeatTimeout() {
        Swift.print("heartbeat timeout")

        sync {
            self.pendingHeartbeatRef = nil
            
            switch state {
            case .closed, .closing:
                // NOOP
                return
            case .open(let ws), .connecting(let ws):
                ws.close()
                // TODO: shouldn't this be an errored state?
                self.state = .closed

                let subject = self.subject
                notifySubjectQueue.async { subject.send(.close) }
            }
        }
    }
    
    func cancelHeartbeatTimer() {
        self.heartbeatTimer = nil
    }
    
    func createHeartbeatTimer() {
        self.heartbeatTimer = Timer(self.heartbeatInterval, repeat: true) { [weak self] in
            self?.sendHeartbeat()
        }
    }
}

// MARK: WebSocket subscriber

extension Socket {
    typealias WebSocketOutput = Result<WebSocketMessage, Swift.Error>
    typealias WebSocketFailure = Swift.Error

    func makeWebSocketSubscriber(with webSocket: WebSocket) -> AnyCancellable {
        let value: (WebSocketOutput) -> Void = { [weak self] in self?.receive(value: $0) }
        let completion: (Subscribers.Completion<Swift.Error>) -> Void = { [weak self] in self?.receive(completion: $0) }

        return webSocket.sink(receiveCompletion: completion, receiveValue: value)
    }

    private func receive(value: WebSocketOutput) {
        Swift.print("socket input", value)
        
        switch value {
        case .failure(let error):
            Swift.print("WebSocket error, but we are not closed: \(error)")
            let subject = self.subject
            notifySubjectQueue.async { subject.send(.websocketError(error)) }
        case .success(let message):
            switch message {
            case .open:
                sync {
                    _reconnectAttempts = 0
                    
                    switch state {
                    case .closed:
                        assertionFailure("We shouldn't receive an open message if we are in a closed state")
                        return
                    case .closing:
                        assertionFailure("We shouldn't recieve an open message if we are in a closing state")
                        return
                    case .open:
                        // NOOP
                        return
                    case .connecting(let ws):
                        self.state = .open(ws)

                        let subject = self.subject
                        notifySubjectQueue.async { subject.send(.open) }

                        flushAsync()
                    }
                }
            case .data:
                assertionFailure("We are not currently expecting any data frames from the server")
            case .string(let string):
                do {
                    let message = try IncomingMessage(string: string)
                    let subject = self.subject

                    sync {
                        switch message.event {
                        case .heartbeat where pendingHeartbeatRef != nil && message.ref == pendingHeartbeatRef:
                            self.pendingHeartbeatRef = nil
                        case .close:
                            notifySubjectQueue.async { subject.send(.incomingMessage(message)) }
                            removeChannel(for: message.topic)
                        default:
                            notifySubjectQueue.async { subject.send(.incomingMessage(message)) }
                        }
                    }
                } catch {
                    Swift.print("Could not decode the WebSocket message data: \(error)")
                    Swift.print("Message data: \(string)")
                    let subject = self.subject
                    notifySubjectQueue.async { subject.send(.unreadableMessage(string)) }
                }
            }
        }
    }
    
    private func receive(completion: Subscribers.Completion<WebSocketFailure>) {
        sync {
            switch state {
            case .closed:
                return
            case .open, .connecting, .closing:
                self.state = .closed
                self.webSocketSubscriber = nil

                let subject = self.subject
                notifySubjectQueue.async { subject.send(.close) }

                if shouldReconnect {
                    _reconnectAttempts += 1
                    let deadline = DispatchTime.now().advanced(by: reconnectTimeInterval(_reconnectAttempts))
                    backgroundQueue.asyncAfter(deadline: deadline) {
                        self.connect()
                    }
                }
            }
        }
    }
}
