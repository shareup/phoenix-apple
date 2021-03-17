import Foundation

public extension Socket {
    enum Message {
        case close
        case connecting
        case open
        case closing
        case incomingMessage(IncomingMessage)
        case unreadableMessage(String)
        case websocketError(Swift.Error)
    }
}
