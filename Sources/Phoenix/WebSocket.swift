import Foundation
import Combine

public class WebSocket: NSObject, WebSocketProtocol {
    public typealias Message = URLSessionWebSocketTask.Message
    
    public enum Errors: Error {
        case unopened
        case invalidURL(URL)
        case invalidURLComponents(URLComponents)
        case notOpen
        case closed(URLSessionWebSocketTask.CloseCode, Data?)
    }
    
    private enum State {
        case connecting
        case open(URLSessionWebSocketTask)
        case closing
        case closed(Errors)
    }
    
    public var isOpen: Bool { get { sync {
        guard case .open = _state else { return false }
        return true
    } } }
    
    public var isClosed: Bool { get { sync {
        guard case .closed = _state else { return false }
        return true
    } } }
    
    private let _url: URL
    private var _state: State
    
    private var _subscriptions: [WebSocketSubscription] = []
    
    private let _delegateQueue: OperationQueue = OperationQueue()
    
    private lazy var _synchronizationQueue: DispatchQueue = {
        let queue = DispatchQueue(label: "Phoenix.WebSocket._synchronizationQueue")
        queue.setSpecific(key: self._queueKey, value: self._queueContext)
        return queue
    }()
    private let _queueKey = DispatchSpecificKey<Int>()
    private lazy var _queueContext: Int = unsafeBitCast(self, to: Int.self)
    
    public required init(url original: URL) throws {
        let appended = original.appendingPathComponent("websocket")
        
        guard var components = URLComponents(url: appended, resolvingAgainstBaseURL: false) else {
            throw Errors.invalidURL(appended)
        }
        
        var query = components.queryItems ?? []
        query.append(URLQueryItem(name: "vsn", value: "2.0.0"))
        
        components.queryItems = query
        
        guard let url = components.url else {
            throw Errors.invalidURLComponents(components)
        }
        
        _url = url
        _state = .closed(.unopened)
        
        super.init()
        
        connect()
    }
    
    private func connect() {
        sync {
            guard case .closed = _state else { return }
            
            let _session = URLSession(configuration: .default, delegate: self, delegateQueue: _delegateQueue)
            
            let task = _session.webSocketTask(with: _url)
            task.receive { result in self.publish(result) }
            task.resume()
        }
    }
    
    public func send(_ message: Message, completionHandler: @escaping (Error?) -> Void) throws {
        try sync {
            guard case .open(let task) = _state else {
                throw Errors.notOpen
            }
            
            task.send(message, completionHandler: completionHandler)
        }
    }
    
    public func close() {
        sync {
            guard case .open(let task) = _state else { return }
            
            task.cancel(with: .normalClosure, reason: nil)
            _state = .closing
        }
    }
}

extension WebSocket: Publisher {
    public typealias Output = Result<Message, Error>
    public typealias Failure = Error
    
    public func receive<S>(subscriber: S) where S : Subscriber, WebSocket.Failure == S.Failure, WebSocket.Output == S.Input {
        sync {
            let subscription = WebSocketSubscription(subscriber: AnySubscriber(subscriber))
            subscriber.receive(subscription: subscription)
            _subscriptions.append(subscription)
        }
    }
    
    private func publish(_ output: Output) {
        sync {
            for subscription in _subscriptions {
                guard let demand = subscription.demand else { return }
                guard demand > 0 else { return }
                
                let newDemand = subscription.subscriber.receive(output)
                subscription.demand = newDemand
            }
        }
    }
    
    private func complete() {
        complete(.finished)
    }
    
    private func complete(_ failure: Failure) {
        complete(.failure(failure))
    }
    
    private func complete(_ failure: Subscribers.Completion<Failure>) {
        sync {
            for subscription in _subscriptions {
                subscription.subscriber.receive(completion: failure)
            }
            _subscriptions.removeAll()
        }
    }
}

extension WebSocket: URLSessionWebSocketDelegate {
    public func urlSession(_ session: URLSession,
                           webSocketTask: URLSessionWebSocketTask,
                           didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
                           reason: Data?) {
        sync {
            _state = .closed(Errors.closed(closeCode, reason))
            
            if closeCode == .normalClosure {
                complete()
            } else {
                complete(Errors.closed(closeCode, reason))
            }
        }
    }
    
    public func urlSession(_ session: URLSession,
                           webSocketTask: URLSessionWebSocketTask,
                           didOpenWithProtocol protocol: String?) {
        sync {
            _state = .open(webSocketTask)
        }
    }
}

extension WebSocket {
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
