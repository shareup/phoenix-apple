import Foundation

public struct Ref: Comparable, CustomStringConvertible, Hashable, ExpressibleByIntegerLiteral,
    Sendable
{
    public let rawValue: UInt64

    init(_ rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public init(integerLiteral value: UInt64) {
        rawValue = value
    }

    var next: Ref { rawValue < maxSafeInt ? Ref(rawValue + 1) : Ref(0) }

    public var description: String { "\(rawValue)" }

    public static func == (lhs: Ref, rhs: Ref) -> Bool {
        lhs.rawValue == rhs.rawValue
    }

    public static func < (lhs: Ref, rhs: Ref) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Number/MAX_SAFE_INTEGER
// https://github.com/phoenixframework/phoenix/blob/2e67c0c4b52566410c536a94b0fdb26f9455591c/assets/test/socket_test.js#L466
private let maxSafeInt: UInt64 = 9_007_199_254_740_991
