import Foundation

extension Socket {
    public enum Message {
        case closed
        case opened
        case incomingMessage(IncomingMessage)
        case unreadableMessage(String)
        case websocketError(Swift.Error)
    }
}
