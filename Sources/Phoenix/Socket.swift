import Foundation
import Combine
import Synchronized

final class Socket: Synchronized {
    private lazy var _channels: [String: Channel] = [:]
    
    private var _ws: WebSocket
    
    public init(url: URL) throws {
        _ws = try WebSocket(url: url)
    }
    
    public var isOpen: Bool { _ws.isOpen }
    public var isClosed: Bool { _ws.isClosed }
}

extension Socket {
    public func join(_ topic: String) -> Channel {
        sync {
            let channel = Channel(topic: topic)
            _channels[topic] = channel
            
            publisher(for: topic).subscribe(channel)
            
            return channel
        }
    }
    
    private func publisher(for topic: String) -> AnyPublisher<IncomingMessage, Error> {
        _ws.tryCompactMap { result -> IncomingMessage? in
            switch result {
            case .failure:
                return nil
            case .success(let message):
                switch message {
                case .data:
                    return nil
                case .string(let string):
                    guard let data = string.data(using: .utf8) else { return nil }
                    return try IncomingMessage.init(data: data)
                @unknown default:
                    return nil
                }
            }
        }
        .filter { $0.topic == topic }
        .eraseToAnyPublisher()
    }
}
