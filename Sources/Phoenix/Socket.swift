import Combine
import Forever
import Foundation
import SimplePublisher
import Synchronized

public final class Socket: Synchronized {
    public typealias Output = Socket.Message
    public typealias Failure = Never
    
    private var subject = SimpleSubject<Output, Failure>()
    private var canceller = CancelDelegator()
    private var state: State = .closed
    private var shouldReconnect = true
    private var channels = [String: WeakChannel]()
    
    public var joinedChannels: [Channel] {
        var _channels: [Channel] = []
        
        sync {
            for (_, weakChannel) in channels {
                if let channel = weakChannel.channel {
                    _channels.append(channel)
                }
            }
        }
        
        return _channels
    }
    
    private var pending: [Push] = []
    private var waitToFlush: Int = 0
    
    private let refGenerator: Ref.Generator
    public let url: URL
    public let timeout: Int
    public let heartbeatInterval: Int
    
    private let heartbeatPush = Push(topic: "phoenix", event: .heartbeat)
    private var pendingHeartbeatRef: Ref? = nil
    private var heartbeatTimerCancellable: Cancellable? = nil
    
    public static let defaultTimeout: Int = 10_000 // TODO: use TimeInterval
    public static let defaultHeartbeatInterval: Int = 30_000 // TODO: use TimeInterval
    static let defaultRefGenerator = Ref.Generator()
    
    public var currentRef: Ref { refGenerator.current }
    
    public var isClosed: Bool { sync {
        guard case .closed = state else { return false }
        return true
    } }
    
    public var isConnecting: Bool { sync {
        guard case .connecting = state else { return false }
        return true
    } }
    
    public var isOpen: Bool { sync {
        guard case .open = state else { return false }
        return true
    } }
    
    public var isClosing: Bool { sync {
        guard case .closing = state else { return false }
        return true
    } }
    
    public var connectionState: String { sync {
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
                timeout: Int = Socket.defaultTimeout,
                heartbeatInterval: Int = Socket.defaultHeartbeatInterval) throws {
        self.timeout = timeout
        self.heartbeatInterval = heartbeatInterval
        self.refGenerator = Ref.Generator()
        self.url = try Socket.webSocketURLV2(url: url)
        
        canceller.delegate = self
    }
    
    init(url: URL,
         timeout: Int = Socket.defaultTimeout,
         heartbeatInterval: Int = Socket.defaultHeartbeatInterval,
         refGenerator: Ref.Generator) throws {
        self.timeout = timeout
        self.heartbeatInterval = heartbeatInterval
        self.refGenerator = refGenerator
        self.url = try Socket.webSocketURLV2(url: url)
        
        canceller.delegate = self
    }
}

// MARK: Phoenix socket URL

extension Socket {
    static func webSocketURLV2(url original: URL) throws -> URL {
        return original
            .appendingPathComponent("websocket")
            .appendingQueryItems(["vsn": "2.0.0"])
    }
}

// MARK: :Publisher

extension Socket: Publisher {
    public func receive<S>(subscriber: S)
        where S: Combine.Subscriber, Failure == S.Failure, Output == S.Input {
        subject.receive(subscriber: subscriber)
    }
    
    func publish(_ output: Output) {
        subject.send(output)
    }
}

// MARK: ConnectablePublisher

extension Socket: ConnectablePublisher {
    // This is how I can provide something that knows how to
    // cancel the Socket as an opaque return value to connect() below
    //
    // I could make the Socket cancellable and just have cancel call
    // disconnect, but I don't really like that idea right now
    private struct CancelDelegator: Cancellable {
        weak var delegate: Socket?
        
        func cancel() {
            delegate?.disconnect()
        }
    }

    @discardableResult public func connect() -> Cancellable {
        sync {
            self.shouldReconnect = true
            
            switch state {
            case .closed:
                subject.send(.connecting)
                
                let ws = WebSocket(url: url)
                self.state = .connecting(ws)
                
                internallySubscribe(ws)
                cancelHeartbeatTimer()
                createHeartbeatTimer()
                
                return canceller
            case .connecting, .open:
                // NOOP
                return canceller
            case .closing:
                // let the reconnect logic handle this case
                return canceller
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
                subject.send(.closing)
                ws.close()
            }
        }
    }
}

// MARK: join

extension Socket {
    public func join(_ topic: String, payload: Payload = [:]) -> Channel {
        sync {
            let _channel = channel(topic, payload: payload)
            _channel.join()
            return _channel
        }
    }
    
    public func channel(_ topic: String, payload: Payload = [:]) -> Channel {
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
}

// MARK: push

extension Socket {
    public func push(topic: String, event: PhxEvent) {
        push(topic: topic, event: event, payload: [:])
    }
    
    public func push(topic: String, event: PhxEvent, payload: Payload) {
        push(topic: topic, event: event, payload: payload) { _ in }
    }
    
    public func push(topic: String,
                     event: PhxEvent,
                     payload: Payload,
                     callback: @escaping Callback) {
        let thePush = Socket.Push(topic: topic,
                                  event: event,
                                  payload: payload,
                                  callback: callback)
        
        sync {
            pending.append(thePush)
        }
        
        DispatchQueue.global().async {
            self.flushNow()
        }
    }
}

// MARK: flush

extension Socket {
    private func flush() {
        assert(waitToFlush == 0)
        
        sync {
            guard case .open = state else { return }
            
            guard let push = pending.first else { return }
            self.pending = Array(self.pending.dropFirst())
            
            let ref = refGenerator.advance()
            let message = OutgoingMessage(push, ref: ref)
            
            send(message) { error in
                if let error = error {
                    Swift.print("Couldn't write to Socket – \(error) - \(message)")
                    self.flushAfterDelay()
                } else {
                    self.flushNow()
                }
                push.asyncCallback(error)
            }
        }
    }
    
    private func flushNow() {
        sync {
            guard waitToFlush == 0 else { return }
        }
        DispatchQueue.global().async { self.flush() }
    }
    
    private func flushAfterDelay() {
        flushAfterDelay(milliseconds: 200)
    }
    
    private func flushAfterDelay(milliseconds: Int) {
        sync {
            guard waitToFlush == 0 else { return }
            self.waitToFlush = milliseconds
        }
        
        let deadline = DispatchTime.now().advanced(by: .milliseconds(waitToFlush))

        DispatchQueue.global().asyncAfter(deadline: deadline) {
            self.sync {
                self.waitToFlush = 0
                self.flushNow()
            }
        }
    }
}

// MARK: send

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
                    completionHandler(error)
                    
                    if let error = error {
                        Swift.print("Error writing to WebSocket: \(error)")
                        ws.close(.abnormalClosure)
                    }
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
                    completionHandler(error)
                    
                    if let error = error {
                        Swift.print("Error writing to WebSocket: \(error)")
                        ws.close(.abnormalClosure)
                    }
                }
            default:
                completionHandler(Socket.Error.notOpen)
            }
        }
    }
}
    
// MARK: heartbeat

extension Socket {
    func sendHeartbeat() {
        sync {
            guard pendingHeartbeatRef == nil else {
                heartbeatTimeout()
                return
            }
            
            self.pendingHeartbeatRef = refGenerator.advance()
            let message = OutgoingMessage(heartbeatPush, ref: pendingHeartbeatRef!)
            
            Swift.print("writing heartbeat")
            
            send(message) { error in
                if let error = error {
                    Swift.print("error writing heartbeat push", error)
                    self.heartbeatTimeout()
                }
            }
        }
    }
    
    func heartbeatTimeout() {
        Swift.print("heartbeat timeout")
        
        self.pendingHeartbeatRef = nil
        
        switch state {
        case .closed, .closing:
            // NOOP
            return
        case .open(let ws), .connecting(let ws):
            ws.close()
            subject.send(.close)
            self.state = .closed
        }
    }
    
    func cancelHeartbeatTimer() {
        heartbeatTimerCancellable?.cancel()
        self.heartbeatTimerCancellable = nil
    }
    
    func createHeartbeatTimer() {
        let interval = TimeInterval(Float(self.heartbeatInterval) / Float(1_000))
        
        let sub = Timer.publish(every: interval, on: .main, in: .common)
                    .autoconnect()
                    .forever { [weak self] _ in self?.sendHeartbeat() }
        
        self.heartbeatTimerCancellable = sub
    }
    
    func heartbeatTimerTick(_ timer: Timer) {
        Swift.print("tick")
    }
}

// MARK: :Subscriber

extension Socket: DelegatingSubscriberDelegate {
    // Creating an indirect internal Subscriber sub-type so the methods can remain internal
    typealias SubscriberInput = Result<WebSocket.Message, Swift.Error>
    typealias SubscriberFailure = Swift.Error
    
    func receive(_ input: SubscriberInput) {
        Swift.print("socket input", input)
        
        switch input {
        case .success(let message):
            switch message {
            case .open:
                // TODO: check if we are already open
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
                    subject.send(.open)
                    
                    sync {
                        joinedChannels.forEach { channel in
                            channel.rejoin()
                        }
                    }
                    
                    flushNow()
                }

            case .data:
                // TODO: Are we going to use data frames from the server for anything?
                assertionFailure("We are not currently expecting any data frames from the server")
            case .string(let string):
                do {
                    let message = try IncomingMessage(data: Data(string.utf8))
                    
                    if message.event == .heartbeat && pendingHeartbeatRef != nil && message.ref == pendingHeartbeatRef {
                        Swift.print("heartbeat OK")
                        self.pendingHeartbeatRef = nil
                    } else {
                        subject.send(.incomingMessage(message))
                    }
                } catch {
                    Swift.print("Could not decode the WebSocket message data: \(error)")
                    Swift.print("Message data: \(string)")
                    subject.send(.unreadableMessage(string))
                }
            }
        case .failure(let error):
            Swift.print("WebSocket error, but we are not closed: \(error)")
            subject.send(.websocketError(error))
        }
    }
    
    func receive(completion: Subscribers.Completion<SubscriberFailure>) {
        sync {
            switch state {
            case .closed:
                // NOOP
                return
            case .open, .connecting, .closing:
                self.state = .closed
                
                subject.send(.close)

                joinedChannels.forEach { channel in
                    channel.remoteClosed(Channel.Error.lostSocket)
                }
                
                if shouldReconnect {
                    DispatchQueue.global().asyncAfter(deadline: DispatchTime.now().advanced(by: .milliseconds(200))) {
                        self.connect()
                    }
                }
            }
        }
    }
}

// MARK: subscribe

extension Socket {
    func subscribe(channel: Channel) {
        channel.internallySubscribe(
            self.compactMap {
                guard case .incomingMessage(let message) = $0 else {
                    return nil
                }
                return message
            }.filter {
                $0.topic == channel.topic
            }
        )
    }
}
