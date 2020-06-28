import Combine
import Foundation
import Synchronized

class WebSocket: NSObject, WebSocketProtocol, Publisher {
    typealias Output = Result<WebSocketMessage, Swift.Error>
    typealias Failure = Swift.Error

    private enum State {
        case unopened
        case connecting
        case open(URLSessionWebSocketTask)
        case closing
        case closed(WebSocketError)
    }
    
    var isOpen: Bool { sync {
        guard case .open = state else { return false }
        return true
    } }
    
    var isClosed: Bool { sync {
        guard case .closed = state else { return false }
        return true
    } }

    private let lock: RecursiveLock = RecursiveLock()
    private func sync<T>(_ block: () throws -> T) rethrows -> T { return try lock.locked(block) }

    private let url: URL
    private var state: State = .unopened
    private let subject = PassthroughSubject<Output, Failure>()

    private let serialQueue: DispatchQueue = DispatchQueue(label: "WebSocket.serialQueue")
    private lazy var delegateQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "WebSocket.delegateQueue"
        queue.maxConcurrentOperationCount = 1
        queue.underlyingQueue = serialQueue
        return queue
    }()
    
    required init(url: URL) {
        self.url = url
        
        super.init()
        
        connect()
    }

    func receive<S: Subscriber>(subscriber: S)
        where S.Input == Result<WebSocketMessage, Swift.Error>, S.Failure == Swift.Error
    {
        subject.receive(subscriber: subscriber)
    }

    private func connect() {
        sync {
            switch (state) {
            case .closed, .unopened:
                state = .connecting
                let session = URLSession(configuration: .default, delegate: self, delegateQueue: delegateQueue)
                let task = session.webSocketTask(with: url)
                task.receive() { [weak self] in self?.receiveFromWebSocket($0) }
                task.resume()
            default:
                return
            }
        }
    }
    
    private func receiveFromWebSocket(_ result: Result<URLSessionWebSocketTask.Message, Error>) {
        let _result = result.map { WebSocketMessage($0) }

        subject.send(_result)
        
        sync {
            if case .open(let task) = state,
                case .running = task.state {
                task.receive() { [weak self] in self?.receiveFromWebSocket($0) }
            }
        }
    }
    
    func send(_ string: String, completionHandler: @escaping (Error?) -> Void) {
        send(.string(string), completionHandler: completionHandler)
    }
    
    func send(_ data: Data, completionHandler: @escaping (Error?) -> Void) {
        send(.data(data), completionHandler: completionHandler)
    }
    
    private func send(_ message: URLSessionWebSocketTask.Message, completionHandler: @escaping (Error?) -> Void) {
        // TODO: capture obj-c exceptions over in the WebSocket class
        
        sync {
            guard case .open(let task) = state else {
                completionHandler(WebSocketError.notOpen)
                return
            }
            
            task.send(message, completionHandler: completionHandler)
        }
    }
    
    func close() {
        close(.goingAway)
    }
    
    // TODO: make a list of close codes to expose publicly instead of depending on URLSessionWebSocketTask.CloseCode
    func close(_ closeCode:  URLSessionWebSocketTask.CloseCode) {
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
    func urlSession(_ session: URLSession,
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

    func urlSession(_ session: URLSession,
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

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        session.invalidateAndCancel()
    }
}
