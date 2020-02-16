import Foundation

extension Channel {
    enum JoinTimer {
        case off
        case joining(timer: Timer, attempt: Int)
        case rejoin(timer: Timer, attempt: Int)
    }
}
