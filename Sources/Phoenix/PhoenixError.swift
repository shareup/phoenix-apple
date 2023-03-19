import Foundation

public enum PhoenixError: Error, Equatable, Sendable {
    case couldNotDecodeMessage
    case couldNotEncodePush
    case disconnect
    case heartbeatTimeout
    case invalidReply
    case joinError(String)
    case leavingChannel
}
