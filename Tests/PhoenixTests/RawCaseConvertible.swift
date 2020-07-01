@testable import Phoenix

protocol RawCaseConvertible {
    associatedtype RawCase: Hashable

    func toRawCase() -> RawCase
}

extension RawCaseConvertible {
    func matches(_ rawCase: RawCase) -> Bool { self.toRawCase() == rawCase }
}

extension Channel.Event: RawCaseConvertible {
    enum _RawCase { case message, join, leave, error }
    typealias RawCase = _RawCase

    func toRawCase() -> RawCase {
        switch self {
        case .message: return .message
        case .join: return .join
        case .leave: return .leave
        case .error: return .error
        }
    }
}

extension Socket.Message: RawCaseConvertible {
    enum _RawCase { case close, connecting, open, closing, incomingMessage, unreadableMessage, websocketError }
    typealias RawCase = _RawCase

    func toRawCase() -> RawCase {
        switch self {
        case .close: return .close
        case .connecting: return .connecting
        case .open: return .open
        case .closing: return .closing
        case .incomingMessage: return .incomingMessage
        case .unreadableMessage: return .unreadableMessage
        case .websocketError: return .websocketError
        }
    }
}
