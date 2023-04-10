import Foundation
import JSON

public enum PhoenixError: Error, Hashable, Sendable {
    case channelError
    case channelErrorWithResponse(String, String, JSON)
    case couldNotDecodeMessage
    case couldNotEncodePush
    case invalidReply
    case leavingChannel
}
