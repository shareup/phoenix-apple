import Foundation
import Combine

final class Socket {
    private lazy var _synchronizationQueue: DispatchQueue = {
        let queue = DispatchQueue(label: "Phoenix.WebSocket._synchronizationQueue")
        queue.setSpecific(key: self._queueKey, value: self._queueContext)
        return queue
    }()
    private let _queueKey = DispatchSpecificKey<Int>()
    private lazy var _queueContext: Int = unsafeBitCast(self, to: Int.self)
    
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
        let channel = Channel(topic: topic)
        _channels[topic] = channel
        
        publisher(for: topic).subscribe(channel)
        
        return channel
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

extension Socket {
    private func sync<T>(_ block: () throws -> T) rethrows -> T {
        if isSynced {
            return try block()
        } else {
            return try _synchronizationQueue.sync(execute: block)
        }
    }
    
    private func sync(_ block: () throws -> Void) rethrows {
        if isSynced {
            try block()
        } else {
            try _synchronizationQueue.sync(execute: block)
        }
    }
    
    private var isSynced: Bool {
        return DispatchQueue.getSpecific(key: _queueKey) == _queueContext
    }
    
    private func async(_ block: @escaping () -> Void) {
        _synchronizationQueue.async(execute: block)
    }
}
