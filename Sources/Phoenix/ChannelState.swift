extension Channel {
    enum State: CustomStringConvertible {
        case closed
        case joining(Ref)
        case joined(Ref)
        case leaving(joinRef: Ref, leavingRef: Ref)
        case errored(Swift.Error)

        var description: String {
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
