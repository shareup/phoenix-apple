import Foundation
import Combine

public protocol WebSocketProtocol: Publisher where Failure == Error, Output == Result<WebSocket.Message, Error> {
    init(url: URL) throws
    
    func send(_ data: Data, completionHandler: @escaping (Error?) -> Void) throws
    func send(_ string: String, completionHandler: @escaping (Error?) -> Void) throws
    
    func close()
}
