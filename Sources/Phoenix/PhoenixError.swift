import Foundation
import JSON

public enum PhoenixError: Error, Equatable, Sendable {
    case channelError
    case couldNotDecodeMessage
    case couldNotEncodePush
    case disconnect
    case heartbeatTimeout
    case invalidReply
    case joinError
    case leavingChannel
    case pushError(String, String, JSON)
    case socketError
}
