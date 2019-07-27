import Foundation

extension Socket {
    enum Message {
        case closed
        case opened
        case incomingMessage(IncomingMessage)
    }
}
