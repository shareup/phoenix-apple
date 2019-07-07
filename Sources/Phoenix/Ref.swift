import Foundation
import Synchronized

public struct Ref: Comparable, Hashable, ExpressibleByIntegerLiteral {
    let rawValue: UInt64

    public init(_ rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public init(integerLiteral value: UInt64) {
        self.rawValue = value
    }

    public static func == (lhs: Ref, rhs: Ref) -> Bool {
        return lhs.rawValue == rhs.rawValue
    }

    public static func < (lhs: Ref, rhs: Ref) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

extension Ref {
    final class Generator: Synchronized {
        var current: Phoenix.Ref { sync { _current } }

        private var _current: Phoenix.Ref = Phoenix.Ref(0)

        func advance() -> Phoenix.Ref {
            return sync {
                _current = Phoenix.Ref(_current.rawValue + 1)
                return _current
            }
        }
    }
}
