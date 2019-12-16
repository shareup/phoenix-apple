import Foundation
import Combine
import Synchronized
import SimplePublisher

public class WebSocket: NSObject, WebSocketProtocol, Synchronized, SimplePublisher {
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
        guard case .open = state else { return false }
        return true
    } }
    
    public var isClosed: Bool { sync {
        guard case .closed = state else { return false }
        return true
    } }
    
    private let url: URL
    private var state: State
    
    private let delegateQueue = OperationQueue()
    
    public typealias Output = Result<WebSocket.Message, Error>
    public typealias Failure = Error
    public var coordinator = SimpleCoordinator<Output, Failure>()
    
    public required init(url: URL) {
        self.url = url
        state = .closed(.unopened)
        
        super.init()
        
        connect()
    }
    
    private func connect() {
        sync {
            guard case .closed = state else { return }
            
            let session = URLSession(configuration: .default, delegate: self, delegateQueue: delegateQueue)
            let task = session.webSocketTask(with: url)
            task.resume()
            task.receive(completionHandler: receiveFromWebSocket(_:))
        }
    }
    
    private func receiveFromWebSocket(_ result: Result<URLSessionWebSocketTask.Message, Error>) {
        let _result = result.map { WebSocket.Message($0) }
        
        coordinator.receive(_result)
        
        sync {
            if case .open(let task) = state,
                case .running = task.state {
                task.receive(completionHandler: receiveFromWebSocket(_:))
            }
        }
    }
    
    public func send(_ string: String, completionHandler: @escaping (Error?) -> Void) {
        send(.string(string), completionHandler: completionHandler)
    }
    
    public func send(_ data: Data, completionHandler: @escaping (Error?) -> Void) {
        send(.data(data), completionHandler: completionHandler)
    }
    
    private func send(_ message: URLSessionWebSocketTask.Message, completionHandler: @escaping (Error?) -> Void) {
        sync {
            guard case .open(let task) = state else {
                completionHandler(Errors.notOpen)
                return
            }
            
            task.send(message, completionHandler: completionHandler)
        }
    }
    
    public func close() {
        close(.normalClosure)
    }
    
    // TODO: make a list of close codes to expose publicly instead of depending on URLSessionWebSocketTask.CloseCode
    public func close(_ closeCode:  URLSessionWebSocketTask.CloseCode) {
        sync {
            guard case .open(let task) = state else { return }
            state = .closing
            task.cancel(with: closeCode, reason: nil)
        }
    }
}

// MARK: :URLSessionWebSocketDelegate

extension WebSocket: URLSessionWebSocketDelegate {
    public func urlSession(_ session: URLSession,
                           webSocketTask: URLSessionWebSocketTask,
                           didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
                           reason: Data?) {
        sync {
            state = .closed(Errors.closed(closeCode, reason))
        }
        
        if closeCode == .normalClosure {
            coordinator.complete()
        } else {
            coordinator.complete(Errors.closed(closeCode, reason))
        }
    }
    
    public func urlSession(_ session: URLSession,
                           webSocketTask: URLSessionWebSocketTask,
                           didOpenWithProtocol protocol: String?) {
        sync {
            state = .open(webSocketTask)
        }
        
        coordinator.receive(.success(.open))
    }
}
