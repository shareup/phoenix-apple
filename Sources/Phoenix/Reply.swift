import Foundation

public struct Reply {
    let incomingMessage: IncomingMessage
    
    let status: String
    let response: Payload
    
    public var isOk: Bool { return status == "ok" }
    public var isNotOk: Bool { return isOk == false }
}

