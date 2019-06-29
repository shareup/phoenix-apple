import Foundation
import Combine

public protocol WebSocketProtocol: class {
    typealias Message = URLSessionWebSocketTask.Message
    
    var subject: AnySubject<Result<Message, Error>, Error> { get }
    
    init(url: URL) throws
    
    func send(_ message: Message, completionHandler: @escaping (Error?) -> Void) throws
    func close()
}
