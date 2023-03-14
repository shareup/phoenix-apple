import Foundation

public enum PhoenixError: Error, Equatable {
    case couldNotEncodePush
    case couldNotDecodeMessage
    case disconnect
    case heartbeatTimeout
}