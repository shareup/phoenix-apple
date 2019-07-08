import Foundation
import Combine
import Synchronized
import Forever

final class Socket: Synchronized {
    enum Errors: Error {
        case closed
    }
    
    var generator = Ref.Generator()
    
    private let _ws: WebSocket
    
    public init(url: URL) throws {
        self._ws = try WebSocket(url: url)
    }
    
    public var isOpen: Bool { _ws.isOpen }
    public var isClosed: Bool { _ws.isClosed }
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
        
        let encoder = JSONEncoder()
        let data: Data
        
        do {
            data = try encoder.encode(message)
        } catch {
            fatalError("Could not serialize OutgoingMessage \(error)")
        }

        _ws.send(.data(data)) { error in
            completionHandler(error)
            
            if let error = error {
                print("Error writing to WebSocket: \(error)")
                self._ws.close(.abnormalClosure)
            }
        }
    }
    
    private func incomingMessagePublisher() -> AnyPublisher<IncomingMessage, Error> {
        return _ws
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
                @unknown default:
                    return nil
                }
            }
            .eraseToAnyPublisher()
    }
    
//    private func repliesPublisher() -> AnyPublisher<Channel.Reply, Error> {
//        return incomingMessagePublisher()
//            .filter {
//                guard case .reply = $0.event else { return false }
//                return true
//            }
//            .compactMap { message -> Channel.Reply? in
//                Channel.Reply(incomingMessage: message)
//            }
//            .eraseToAnyPublisher()
//    }
    
    private func channelPublisher(for topic: String) -> AnyPublisher<IncomingMessage, Error> {
        return incomingMessagePublisher()
            .filter { $0.topic == topic }
            .eraseToAnyPublisher()
    }
}
