import Foundation

extension Socket {
    public enum Message {
        case close
        case open
        case incomingMessage(IncomingMessage)
        case unreadableMessage(String)
        case websocketError(Swift.Error)
    }
}
