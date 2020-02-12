extension Channel {
    public enum Error: Swift.Error {
        case invalidJoinReply(Channel.Reply)
        case isClosed
        case lostSocket
        case noLongerJoining
        case timeout
    }
}
