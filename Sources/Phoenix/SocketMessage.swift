import Foundation

extension Socket {
    public enum Message {
        case close
        case connecting
        case open
        case closing
        case incomingMessage(IncomingMessage)
        case unreadableMessage(String)
        case websocketError(Swift.Error)
    }
}
