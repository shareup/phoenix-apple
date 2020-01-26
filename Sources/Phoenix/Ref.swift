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

let maxSafeInt: UInt64 = 9007199254740991

extension Ref {
    final class Generator: Synchronized {
        var current: Ref { sync { _current } }

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
                    _current = Ref(1)
                }
                
                return _current
            }
        }
        
        static var global: Generator = Generator()
    }
}
