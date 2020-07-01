import Combine
import Foundation

public protocol WebSocketSendable { }
extension Data: WebSocketSendable { }
extension String: WebSocketSendable { }

public enum WebSocketMessage {
    case data(Data)
    case string(String)
    case open
}

public protocol WebSocketProtocol: Publisher where Failure == Error, Output == Result<WebSocketMessage, Error> {
    init(url: URL) throws
    
    func send<T: WebSocketSendable>(_ sendable: T, completionHandler: @escaping (Error?) -> Void) throws
    func send(_ data: Data, completionHandler: @escaping (Error?) -> Void) throws
    func send(_ string: String, completionHandler: @escaping (Error?) -> Void) throws
    
    func close()
}

extension WebSocketProtocol {
    public func send<T: WebSocketSendable>(
        _ sendable: T,
        completionHandler: @escaping (Error?) -> Void) throws
    {
        if let string = sendable as? String {
            try self.send(string, completionHandler: completionHandler)
        } else if let data = sendable as? Data {
            try self.send(data, completionHandler: completionHandler)
        } else {
            preconditionFailure("\(sendable) must be either String or Data")
        }
    }
}


