import Foundation

extension Channel {
    enum JoinTimer {
        /// Channel is not trying to be joined or rejoined.
        case off

        /// Channel is trying to be joined. When the timer fires, the join
        /// should be cancelled.
        case join(timer: Timer, attempt: Int)

        /// Channel is trying to be rejoined. In this case, the timer signifies
        /// the next time a join attempt should be made.
        case rejoin(timer: Timer, attempt: Int)

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
    }
}
