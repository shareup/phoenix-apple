public enum ChannelError: Error {
    case invalidJoinReply(Channel.Reply)
    case isClosed
}
