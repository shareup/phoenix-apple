import Foundation
import Combine
import Synchronized
import Forever
import SimplePublisher
import Atomic

typealias SocketSendCallback = (Error?) -> Void

public final class Socket: Synchronized {
    enum SocketError: Error {
        case closed
    }

    enum State {
        case open
        case closed
    }
    
    @Atomic(true) var shouldReconnect: Bool

    public typealias Output = Socket.Message
    public typealias Failure = Error
    
    private var subject = SimpleSubject<Output, Failure>()
    private var ws: WebSocket?
    private var internalSubscriber: Subscriber?
    
    private var state: State = .closed
    
    private var channels = [String: WeakChannel]()
    
    public let url: URL
    
    public var isOpen: Bool { sync {
        guard case .open = state else { return false }
        return true
    } }

    public var isClosed: Bool { sync {
        guard case .closed = state else { return false }
        return true
    } }
    
    public init(url: URL) throws {
        self.url = try Self.webSocketURLV2(url: url)
        self.internalSubscriber = Subscriber(socket: self)
        connect()
    }
    
    public func close() {
        self.shouldReconnect = false
        ws?.close()
    }
    
    private func connect() {
        self.ws = WebSocket(url: url)
        ws!.subscribe(internalSubscriber!)
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

extension Socket {
    // Creating an indirect internal Subscriber sub-type so the methods can remain internal
    
    func receive(_ input: Result<WebSocket.Message, Error>) {
        switch input {
        case .success(let message):
            switch message {
            case .open:
                // TODO: check if we are already open
                self.state = .open
                subject.send(.opened)
                
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
    
    func receive(completion: Subscribers.Completion<Error>) {
        // TODO: check if we are already closed
        
        sync {
            self.internalSubscriber?.cancel()
            self.ws = nil
            self.state = .closed
            
            subject.send(.closed)
            
            for (_, weakChannel) in channels {
                if let channel = weakChannel.channel {
                    channel.left()
                }
            }
        }

        if shouldReconnect {
            DispatchQueue.global().asyncAfter(deadline: DispatchTime.now().advanced(by: .milliseconds(200))) {
                self.connect()
            }
        } else {
            subject.send(completion: .finished)
        }
    }
    
    class Subscriber: Combine.Subscriber, Synchronized {
        weak var socket: Socket?
        private var subscription: Subscription?
        
        typealias Input = Result<WebSocket.Message, Error>
        typealias Failure = Error
        
        init(socket: Socket) {
            self.socket = socket
        }

        func receive(subscription: Subscription) {
            subscription.request(.unlimited)

            sync {
                self.subscription = subscription
            }
        }

        func receive(_ input: Result<WebSocket.Message, Error>) -> Subscribers.Demand {
            socket?.receive(input)
            return .unlimited
        }

        func receive(completion: Subscribers.Completion<Error>) {
            socket?.receive(completion: completion)
        }
        
        func cancel() {
            sync {
                self.subscription?.cancel()
                self.subscription = nil
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
            completionHandler(SocketError.closed)
            return
        }
        
        let data: Data
        
        do {
            data = try message.encoded()
        } catch {
            // TODO: make this throw instead
            fatalError("Could not serialize OutgoingMessage \(error)")
        }

        ws.send(data) { error in
            completionHandler(error)
            
            if let error = error {
                Swift.print("Error writing to WebSocket: \(error)")
                ws.close(.abnormalClosure)
            }
        }
    }

    private func subscribe(channel: Channel) {
        self
            .compactMap {
                guard case .incomingMessage(let message) = $0 else {
                    return nil
                }
                return message
            }
            .filter { $0.topic == channel.topic }
            .subscribe(channel)
    }
}
