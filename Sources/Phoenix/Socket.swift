import Foundation
import Combine
import Synchronized
import Forever

final class Socket: Synchronized {
    enum Errors: Error {
        case closed
    }
    
    var shouldReconnect = true
    var generator = Ref.Generator()
    
    private let ws: WebSocket
    
    private var channels = [String: WeakChannel]()
    
    public var isOpen: Bool { ws.isOpen }
    public var isClosed: Bool { ws.isClosed }
    
    public init(url: URL) throws {
        self.ws = try WebSocket(url: url)
    }
    
    public func close() {
        ws.close()
        self.shouldReconnect = false
    }
}

extension Socket {
    static func webSocketURLV2(url original: URL) throws -> URL {
        return original
            .appendingPathComponent("websocket")
            .appendingQueryItems(["vsn": "2.0.0"])
    }
}

extension Socket {
    public func join(_ topic: String) -> Channel {
        sync {
            if let weakChannel = channels[topic],
                let channel = weakChannel.channel {
                return channel
            }
            
            let channel = Channel(topic: topic, socket: self)
            
            channels[topic] = WeakChannel(channel)
            subscribe(channel)
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
    
    private func subscribe(_ channel: Channel) {
        ws
        .compactMap { result -> WebSocket.Message? in
            switch result {
            case .failure: return nil
            case .success(let message): return message
            }
        }.tryCompactMap { message -> IncomingMessage? in
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
        .filter { $0.topic == channel.topic }
        .subscribe(channel)
    }
}

extension Socket {
    final class WeakChannel {
        weak var channel: Channel?
        
        init(_ channel: Channel) {
            self.channel = channel
        }
    }
}
