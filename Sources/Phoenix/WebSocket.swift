import Foundation
import Combine
import Synchronized

public class WebSocket: NSObject, WebSocketProtocol, Synchronized {
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
    
    public var isOpen: Bool { sync {
        guard case .open = _state else { return false }
        return true
    } }
    
    public var isClosed: Bool { sync {
        guard case .closed = _state else { return false }
        return true
    } }
    
    private let _url: URL
    private var _state: State
    
    private var _subscriptions: [WebSocketSubscription] = []
    private let _delegateQueue: OperationQueue = OperationQueue()
    
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
            task.resume()
            task.receive(completionHandler: receiveFromWebSocket(result:))
        }
    }
    
    private func receiveFromWebSocket(result: Result<URLSessionWebSocketTask.Message, Error>) {
        
        publish(result)
        
        sync {
            if case .open(let task) = _state,
                case .running = task.state {
                task.receive(completionHandler: receiveFromWebSocket(result:))
            }
        }
    }
    
    public func send(_ message: Message, completionHandler: @escaping (Error?) -> Void) {
        sync {
            guard case .open(let task) = _state else {
                completionHandler(Errors.notOpen)
                return
            }
            
            task.send(message, completionHandler: completionHandler)
        }
    }
    
    public func close() {
        close(.normalClosure)
    }
    
    public func close(_ closeCode:  URLSessionWebSocketTask.CloseCode) {
        sync {
            guard case .open(let task) = _state else { return }
            
            task.cancel(with: closeCode, reason: nil)
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
                subscription.request(newDemand)
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
