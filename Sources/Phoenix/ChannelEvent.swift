extension Channel {
    public enum Event {
        case message(Channel.Message)
        case join
        case leave
        case error(Swift.Error)
    }
}
