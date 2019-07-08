import Foundation
import Combine
import Synchronized
import Forever

final class Socket: Synchronized {
    enum Errors: Error {
        case closed
    }
    
    var generator = Ref.Generator()
    
    private let ws: WebSocket
    
    public var isOpen: Bool { ws.isOpen }
    public var isClosed: Bool { ws.isClosed }
    
    public init(url: URL) throws {
        self.ws = try WebSocket(url: url)
    }
    
    public func close() {
        ws.close()
    }
}

extension Socket {
    public func join(_ topic: String) -> Channel {
        sync {
            let channel = Channel(topic: topic, socket: self)
            channelPublisher(for: topic).subscribe(channel)
            channel.join()
            return channel
        }
    }

    func send(_ message: OutgoingMessage) {
        send(message, completionHandler: { _ in })
    }
    
    func send(_ message: OutgoingMessage, completionHandler: @escaping (Error?) -> Void) {
        guard isOpen else {
            completionHandler(Errors.closed)
            return
        }
        
        let data: Data
        
        do {
            data = try message.encoded()
        } catch {
            fatalError("Could not serialize OutgoingMessage \(error)")
        }

        ws.send(data) { error in
            completionHandler(error)
            
            if let error = error {
                print("Error writing to WebSocket: \(error)")
                self.ws.close(.abnormalClosure)
            }
        }
    }
    
    private func incomingMessagePublisher() -> AnyPublisher<IncomingMessage, Error> {
        return ws
            .compactMap { result -> WebSocket.Message? in
                switch result {
                case .failure: return nil
                case .success(let message): return message
                }
            }
            .tryCompactMap { message -> IncomingMessage? in
                switch message {
                case .data:
                    // TODO: Are we going to use data frames from the server for anything?
                    return nil
                case .string(let string):
                    guard let data = string.data(using: .utf8) else { return nil }
                    return try IncomingMessage(data: data)
                case .open:
                    return nil
                }
            }
            .eraseToAnyPublisher()
    }
    
    private func channelPublisher(for topic: String) -> AnyPublisher<IncomingMessage, Error> {
        return incomingMessagePublisher()
            .filter { $0.topic == topic }
            .eraseToAnyPublisher()
    }
}
