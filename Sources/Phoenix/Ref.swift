import Synchronized

public struct Ref: Comparable, CustomDebugStringConvertible, Hashable, ExpressibleByIntegerLiteral {
    public let rawValue: UInt64

    public init(_ rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public init(integerLiteral value: UInt64) {
        self.rawValue = value
    }

    public var debugDescription: String { "\(rawValue)" }

    public static func == (lhs: Ref, rhs: Ref) -> Bool {
        return lhs.rawValue == rhs.rawValue
    }

    public static func < (lhs: Ref, rhs: Ref) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

// https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Number/MAX_SAFE_INTEGER
// https://github.com/phoenixframework/phoenix/blob/2e67c0c4b52566410c536a94b0fdb26f9455591c/assets/test/socket_test.js#L466
let maxSafeInt: UInt64 = 9007199254740991

extension Ref {
    final class Generator  {
        var current: Ref { sync { _current } }

        private let lock: RecursiveLock = RecursiveLock()
        private func sync<T>(_ block: () throws -> T) rethrows -> T { return try lock.locked(block) }

        private var _current: Ref
        
        init() {
            self._current = Ref(0)
        }
        
        init(start: Ref) {
            self._current = start
        }

        func advance() -> Phoenix.Ref {
            return sync {
                if (_current.rawValue < maxSafeInt) {
                    _current = Ref(_current.rawValue + 1)
                } else {
                    _current = Ref(0)
                }
                
                return _current
            }
        }
    }
}
