extension Channel {
    enum State: CustomDebugStringConvertible {
        case closed
        case joining(Ref)
        case joined(Ref)
        case leaving(joinRef: Ref, leavingRef: Ref)
        case errored(Swift.Error)

        var debugDescription: String {
            switch self {
            case .closed: return "closed"
            case .joining: return "joining"
            case .joined: return "joined"
            case .leaving: return "leaving"
            case .errored: return "errored"
            }
        }
    }
}
