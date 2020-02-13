extension Channel {
    public enum Error: Swift.Error {
        case invalidJoinReply(Channel.Reply)
        case socketIsClosed
        case lostSocket
        case noLongerJoining
        case timeout
    }
}
