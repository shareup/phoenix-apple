extension Channel {
    enum State {
        case closed
        case joining(Ref)
        case joined(Ref)
        case leaving(joinRef: Ref, leavingRef: Ref)
        case errored(Swift.Error)
    }
}
