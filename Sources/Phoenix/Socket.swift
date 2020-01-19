import Foundation
import Combine
import Synchronized
import Forever
import SimplePublisher
import Atomic

typealias SocketSendCallback = (Swift.Error?) -> Void

public final class Socket: Synchronized {
    enum Error: Swift.Error {
        case closed
    }

    enum State {
        case open
        case closed
    }
    
    public typealias Output = Socket.Message
    public typealias Failure = Swift.Error
    
    private var subject = SimpleSubject<Output, Failure>()
    private var ws: WebSocket?
    
    private var state: State = .closed
    private var shouldReconnect = true
    
    private var channels = [String: WeakChannel]()
    
    private let refGenerator: Ref.Generator
    
    public let url: URL
    public let timeout: Int
    public let heartbeatInterval: Int
    
    public static let defaultTimeout: Int = 10_000
    public static let defaultHeartbeatInterval: Int = 30_000
    static let defaultRefGenerator = Ref.Generator()
    
    public var currentRef: Ref { refGenerator.current }
    
    public var isOpen: Bool { sync {
        guard case .open = state else { return false }
        return true
    } }

    public var isClosed: Bool { sync {
        guard case .closed = state else { return false }
        return true
    } }
    
    public init(url: URL,
                timeout: Int = Socket.defaultTimeout,
                heartbeatInterval: Int = Socket.defaultHeartbeatInterval) throws {
        self.timeout = timeout
        self.heartbeatInterval = heartbeatInterval
        self.refGenerator = Ref.Generator()
        self.url = try Socket.webSocketURLV2(url: url)
        connect()
    }
    
    init(url: URL,
         timeout: Int = Socket.defaultTimeout,
         heartbeatInterval: Int = Socket.defaultHeartbeatInterval,
         refGenerator: Ref.Generator) throws {
        self.timeout = timeout
        self.heartbeatInterval = heartbeatInterval
        self.refGenerator = refGenerator
        self.url = try Socket.webSocketURLV2(url: url)
        connect()
    }
    
    public func disconnect() {
        sync {
            self.shouldReconnect = false
            ws?.close()
        }
    }
    
    public func connect() {
        sync {
            self.shouldReconnect = true
            
            guard ws == nil else { return }
            
            self.ws = WebSocket(url: url)
            internallySubscribe(ws!)
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
                self.state = .open
                subject.send(.open)
                
                sync {
                    for (_, weakChannel) in channels {
                        if let channel = weakChannel.channel {
                            channel.rejoin()
                        }
                    }
                }
            case .data:
                // TODO: Are we going to use data frames from the server for anything?
                assertionFailure("We are not currently expecting any data frames from the server")
            case .string(let string):
                do {
                    let message = try IncomingMessage(data: Data(string.utf8))
                    subject.send(.incomingMessage(message))
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
        // TODO: check if we are already closed
        
        sync {
            self.ws = nil
            self.state = .closed
            
            subject.send(.close)
            
            for (_, weakChannel) in channels {
                if let channel = weakChannel.channel {
                    channel.left()
                }
            }
            
            if shouldReconnect {
                DispatchQueue.global().asyncAfter(deadline: DispatchTime.now().advanced(by: .milliseconds(200))) {
                    self.connect()
                }
            }
        }
    }
}

// MARK: Join and send

extension Socket {
    public func join(_ topic: String) -> Channel {
        sync {
            if let weakChannel = channels[topic],
                let channel = weakChannel.channel {
                return channel
            }
            
            let channel = Channel(topic: topic, socket: self)
            
            channels[topic] = WeakChannel(channel)
            subscribe(channel: channel)
            channel.join()
            
            return channel
        }
    }

    func send(_ message: OutgoingMessage) {
        send(message, completionHandler: { _ in })
    }
    
    func send(_ message: OutgoingMessage, completionHandler: @escaping SocketSendCallback) {
        guard let ws = ws, isOpen else {
            completionHandler(Socket.Error.closed)
            return
        }
        
        let data: Data
        
        do {
            data = try message.encoded()
        } catch {
            // TODO: make this throw instead
            fatalError("Could not serialize OutgoingMessage \(error)")
        }

        // TODO: capture obj-c exceptions
        ws.send(data) { error in
            completionHandler(error)
            
            if let error = error {
                Swift.print("Error writing to WebSocket: \(error)")
                ws.close(.abnormalClosure)
            }
        }
    }

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
