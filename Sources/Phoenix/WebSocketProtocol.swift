import Foundation
import Combine

public protocol WebSocketProtocol: Publisher where Failure == Error, Output == Result<Message, Error> {
    typealias Message = URLSessionWebSocketTask.Message
    
    init(url: URL) throws
    
    func send(_ message: Message, completionHandler: @escaping (Error?) -> Void) throws
    func close()
}
