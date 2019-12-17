import Foundation
import Combine
import Synchronized
import SimplePublisher

public class WebSocket: NSObject, WebSocketProtocol, Synchronized, SimplePublisher {
    private enum State {
        case unopened
        case connecting
        case open(URLSessionWebSocketTask)
        case closing
        case closed(WebSocketError)
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
    private var state: State = .unopened
    
    private let delegateQueue = OperationQueue()
    
    public typealias Output = Result<WebSocket.Message, Error>
    public typealias Failure = Error

    public var subject = SimpleSubject<Output, Failure>()
    
    public required init(url: URL) {
        self.url = url
        
        super.init()
        
        connect()
    }
    
    private func connect() {
        sync {
            switch (state) {
            case .closed, .unopened:
                let session = URLSession(configuration: .default, delegate: self, delegateQueue: delegateQueue)
                let task = session.webSocketTask(with: url)
                task.resume()
                task.receive(completionHandler: receiveFromWebSocket(_:))
            default:
                return
            }
        }
    }
    
    private func receiveFromWebSocket(_ result: Result<URLSessionWebSocketTask.Message, Error>) {
        let _result = result.map { WebSocket.Message($0) }

        subject.send(_result)
        
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
                completionHandler(WebSocketError.notOpen)
                return
            }
            
            task.send(message, completionHandler: completionHandler)
        }
    }
    
    public func close() {
        close(.goingAway)
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

let normalCloseCodes: [URLSessionWebSocketTask.CloseCode] = [.goingAway, .normalClosure]

extension WebSocket: URLSessionWebSocketDelegate {
    public func urlSession(_ session: URLSession,
                           webSocketTask: URLSessionWebSocketTask,
                           didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
                           reason: Data?) {
        sync {
            if case .closed = state { return } // Apple will double close or I would do an assertion failure...
            state = .closed(WebSocketError.closed(closeCode, reason))
        }
        
        if normalCloseCodes.contains(closeCode) {
            subject.send(completion: .finished)
        } else {
            subject.send(completion: .failure(WebSocketError.closed(closeCode, reason)))
        }
    }
    
    public func urlSession(_ session: URLSession,
                           webSocketTask: URLSessionWebSocketTask,
                           didOpenWithProtocol protocol: String?) {
        sync {
            if case .open = state {
                assertionFailure("Received an open event from the networking library, but I think I'm already open")
            }
            state = .open(webSocketTask)
        }

        subject.send(.success(.open))
    }
}
