public extension Channel {
    enum Event {
        case message(Channel.Message)
        case join(Channel.Message)
        case leave
        case error(Swift.Error)
    }
}
