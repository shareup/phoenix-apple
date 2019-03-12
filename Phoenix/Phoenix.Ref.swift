import Foundation

extension Phoenix {
    struct Ref: Comparable, Hashable, ExpressibleByIntegerLiteral {
        private(set) var rawValue: UInt64

        init(_ rawValue: UInt64) {
            self.rawValue = rawValue
        }

        init(integerLiteral value: UInt64) {
            self.rawValue = value
        }

        static func == (lhs: Ref, rhs: Ref) -> Bool {
            return lhs.rawValue == rhs.rawValue
        }

        static func < (lhs: Ref, rhs: Ref) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }
    }
}

extension Phoenix.Ref {
    final class Generator {
        var current: Phoenix.Ref {
            let ref: Phoenix.Ref
            os_unfair_lock_lock(_lock)
            ref = _current
            os_unfair_lock_unlock(_lock)
            return ref
        }

        private var _current: Phoenix.Ref = Phoenix.Ref(0)
        private var _lock: UnsafeMutablePointer<os_unfair_lock>

        init() {
            _lock = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
            _lock.initialize(to: os_unfair_lock())
        }

        deinit {
            _lock.deallocate()
        }

        func advance() -> Phoenix.Ref {
            let next: Phoenix.Ref
            os_unfair_lock_lock(_lock)
            next = Phoenix.Ref(_current.rawValue + 1)
            _current = next
            os_unfair_lock_unlock(_lock)
            return next
        }
    }
}
