import Foundation

extension Channel {
    enum JoinTimer {
        case off
        case joining(timer: Timer, attempt: Int)
        case rejoin(timer: Timer, attempt: Int)
        
        func invalidate() {
            switch self {
            case .off:
                break // NOOP
            case .joining(let timer, _), .rejoin(let timer, _):
                timer.invalidate()
            }
        }
    }
}
