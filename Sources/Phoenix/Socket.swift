import Foundation
import Combine
import Synchronized
import Forever
import SimplePublisher

final class Socket: Synchronized, SimplePublisher {
    enum Errors: Error {
        case closed
    }

    enum State {
        case open
        case closed
    }
    
    var shouldReconnect = true

    typealias Output = Socket.Message
    typealias Failure = Error
    var coordinator = SimpleCoordinator<Output, Failure>()
    
    private var subscription: Subscription? = nil
    private var ws: WebSocket?
    
    private var channels = [String: WeakChannel]()
    private var state = State.closed
    private var pusher = Pusher()
    
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
        connect()
        try? pusher.receiveBatch(callback: receiveFromPusher(_:))
    }

    private func change(to newState: State) {
        sync {
            self.state = newState
        }
    }
    
    public func close() {
        ws?.close()
        self.shouldReconnect = false
    }
    
    private func connect() {
        self.ws = WebSocket(url: url)
        ws!.subscribe(self)
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

// MARK: :Subscriber

extension Socket: Subscriber {
    typealias Input = Result<WebSocket.Message, Error>

    func receive(subscription: Subscription) {
        subscription.request(.unlimited)

        sync {
            self.subscription = subscription
        }
    }

    func receive(_ input: Result<WebSocket.Message, Error>) -> Subscribers.Demand {
        // TODO: where to send this?
        Swift.print("input: \(String(describing: input))")

        switch input {
        case .success(let message):
            switch message {
            case .open:
                change(to: .open)
                coordinator.receive(.opened)
            case .data:
                // TODO: Are we going to use data frames from the server for anything?
                assertionFailure("We are not currently expecting any data frames from the server")
                break
            case .string(let string):
                do {
                    let message = try IncomingMessage(data: Data(string.utf8))
                    coordinator.receive(.incomingMessage(message))
                } catch {
                    Swift.print("Could not decode the WebSocket message data: \(error)")
                    Swift.print("Message data: \(string)")
                    coordinator.receive(.unreadableMessage(string))
                }
            }
        case .failure(let error):
            Swift.print("WebSocket error, but we are not closed: \(error)")
            coordinator.receive(.websocketError(error))
        }

        return .unlimited
    }

    func receive(completion: Subscribers.Completion<Error>) {
        sync {
            self.ws = nil
            self.subscription = nil
            change(to: .closed)
        }
        
        coordinator.receive(.closed)
        
        if shouldReconnect {
            DispatchQueue.global().asyncAfter(deadline: DispatchTime.now().advanced(by: .milliseconds(200))) {
                self.connect()
            }
        } else {
            coordinator.complete()
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
            
            let channel = Channel(topic: topic, pusher: pusher)
            
            channels[topic] = WeakChannel(channel)
            subscribe(channel: channel)
            channel.join()
            
            return channel
        }
    }

    private func receiveFromPusher(_ tracked: [(Pusher.Push, OutgoingMessage)]) {
        for (push, message) in tracked {
            send(message) { error in
                switch push {
                case .socket(let push):
                    // we always notify socket pushes when writing is complete
                    push.asyncCallback(error)
                case .channel(let push):
                    // we only notify channel pushes when there is an error writing, there is a response, or there is a timeout
                    guard let error = error else {
                        return
                    }
                    push.asyncCallback(result: .failure(error))
                }
            }
        }

        try? pusher.receiveBatch(callback: receiveFromPusher(_:))
    }

    private func send(_ message: OutgoingMessage) {
        send(message, completionHandler: { _ in })
    }
    
    private func send(_ message: OutgoingMessage, completionHandler: @escaping (Error?) -> Void) {
        guard let ws = ws, isOpen else {
            completionHandler(Errors.closed)
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
