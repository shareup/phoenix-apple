import Foundation
import Combine
import Synchronized
import Forever
import SimplePublisher
import Atomic

public final class Socket: Synchronized {
    enum Error: Swift.Error {
        case notOpen
    }

    enum State {
        case closed
        case connecting(WebSocket)
        case open(WebSocket)
        case closing(WebSocket)
    }
    
    public typealias Output = Socket.Message
    public typealias Failure = Swift.Error
    
    private var subject = SimpleSubject<Output, Failure>()
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
    }
    
    init(url: URL,
         timeout: Int = Socket.defaultTimeout,
         heartbeatInterval: Int = Socket.defaultHeartbeatInterval,
         refGenerator: Ref.Generator) throws {
        self.timeout = timeout
        self.heartbeatInterval = heartbeatInterval
        self.refGenerator = refGenerator
        self.url = try Socket.webSocketURLV2(url: url)
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
    
    public func connect() {
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
            case .connecting, .open:
                // NOOP
                return
            case .closing:
                // let the reconnect logic handle this case
                return
            }
        }
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
    
    func complete() {
        complete(.finished)
    }
    
    func complete(_ failure: Failure) {
        complete(.failure(failure))
    }
    
    func complete(_ completion: Subscribers.Completion<Failure>) {
        subject.send(completion: completion)
    }
}

// MARK: join

extension Socket {
    public func join(_ topic: String, payload: Payload = [:]) -> Channel {
        sync {
            if let weakChannel = channels[topic],
                let channel = weakChannel.channel {
                return channel
            }
            
            let channel = Channel(topic: topic, socket: self, joinPayload: payload)
            
            channels[topic] = WeakChannel(channel)
            subscribe(channel: channel)
            channel.join()
            
            return channel
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
        sync {
            switch state {
            case .open(let ws):
                let data: Data
                
                do {
                    data = try message.encoded()
                } catch {
                    // TODO: make this call the callback with an error instead
                    preconditionFailure("Could not serialize OutgoingMessage \(error)")
                }

                // TODO: capture obj-c exceptions
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
    typealias Input = Result<WebSocket.Message, Swift.Error>
    
    func internallySubscribe<P>(_ publisher: P)
        where P: Publisher, Input == P.Output, Failure == P.Failure {
            
        let internalSubscriber = DelegatingSubscriber(delegate: self)
        publisher.subscribe(internalSubscriber)
    }
    
    func receive(_ input: Input) {
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
    
    func receive(completion: Subscribers.Completion<Failure>) {
        sync {
            switch state {
            case .closed:
                // NOOP
                return
            case .open, .connecting, .closing:
                self.state = .closed
                
                subject.send(.close)

                joinedChannels.forEach { channel in
                    channel.left()
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
    private func subscribe(channel: Channel) {
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
