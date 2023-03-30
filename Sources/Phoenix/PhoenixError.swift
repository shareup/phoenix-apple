import Foundation

public enum PhoenixError: Error, Equatable, Sendable {
    case couldNotDecodeMessage
    case couldNotEncodePush
    case disconnect
    case heartbeatTimeout
    case invalidReply
    case joinError
    case leavingChannel
    case pushError(String, String, Payload)
    case socketError
}
