import DispatchTimer
import Foundation

extension Channel {
    enum JoinTimer {
        /// Channel is not trying to be joined or rejoined.
        case off

        /// Channel is trying to be joined. When the timer fires, the join
        /// should be cancelled.
        case join(timer: DispatchTimer, attempt: Int)

        /// Channel is trying to be rejoined. In this case, the timer signifies
        /// the next time a join attempt should be made.
        case rejoin(timer: DispatchTimer, attempt: Int)

        var attempt: Int? {
            switch self {
            case .off:
                return nil
            case let .join(_, attempt):
                return attempt
            case let .rejoin(_, attempt):
                return attempt
            }
        }

        var isOn: Bool { isJoinTimer || isRejoinTimer }
        var isOff: Bool { isOn == false }

        var isJoinTimer: Bool {
            switch self {
            case .off: return false
            case .join: return true
            case .rejoin: return false
            }
        }

        var isNotRejoinTimer: Bool { isRejoinTimer == false }
        var isRejoinTimer: Bool {
            switch self {
            case .off: return false
            case .join: return false
            case .rejoin: return true
            }
        }
    }
}
