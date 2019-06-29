import Foundation
import Combine

public class WebSocket: NSObject, WebSocketProtocol, URLSessionWebSocketDelegate {
    public typealias Message = URLSessionWebSocketTask.Message
    public var subject = PassthroughSubject<Result<Message, Error>, Error>().eraseToAnySubject()
    
    public enum Errors: Error {
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
    
    private let _url: URL
    private var _state: State
    
    private let _delegateQueue: OperationQueue = OperationQueue()
    private let _queue: DispatchQueue = DispatchQueue(label: "Phoenix.WebSocket._queue")
    
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
        _state = .connecting
        
        super.init()
        
        buildWebSocketSessionAndTask()
    }
    
    private func buildWebSocketSessionAndTask() {
        // TODO: accept pre-prepared URLSession as init arg
        let _session = URLSession(configuration: .background(withIdentifier: "Phoenix.Websocket"), delegate: self, delegateQueue: _delegateQueue)
        
        let task = _session.webSocketTask(with: _url)
        task.receive { result in self.subject.send(result) }
        task.resume()
    }
    
    public func urlSession(_ session: URLSession,
                           webSocketTask: URLSessionWebSocketTask,
                           didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
                           reason: Data?) {
        _queue.sync {
            _state = .closed(Errors.closed(closeCode, reason))
            
            if closeCode == .normalClosure {
                subject.send(completion: .finished)
            } else {
                subject.send(completion: .failure(Errors.closed(closeCode, reason)))
            }
        }
    }
    
    public func urlSession(_ session: URLSession,
                           webSocketTask: URLSessionWebSocketTask,
                           didOpenWithProtocol protocol: String?) {
        _queue.sync {
            _state = .open(webSocketTask)
        }
    }
    
    public func send(_ message: Message, completionHandler: @escaping (Error?) -> Void) throws {
        try _queue.sync {
            guard case .open(let task) = _state else {
                throw Errors.notOpen
            }
            
            task.send(message, completionHandler: completionHandler)
        }
    }
    
    public func close() {
        _queue.sync {
            guard case .open(let task) = _state else { return }
            task.cancel(with: .normalClosure, reason: nil)
            _state = .closing
        }
    }
}
