import Foundation
import DispatchTimer

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
            case .join(_, let attempt):
                return attempt
            case .rejoin(_, let attempt):
                return attempt
            }
        }
        
        var isOn: Bool { return self.isJoinTimer || self.isRejoinTimer }
        var isOff: Bool { return self.isOn == false }

        var isJoinTimer: Bool {
            switch self {
            case .off: return false
            case .join: return true
            case .rejoin: return false
            }
        }

        var isNotRejoinTimer: Bool { return self.isRejoinTimer == false }
        var isRejoinTimer: Bool {
            switch self {
            case .off: return false
            case .join: return false
            case .rejoin: return true
            }
        }
    }
}
