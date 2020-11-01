extension Socket {
    enum Error: Swift.Error {
        case notOpen
        case couldNotSerializeOutgoingMessage(OutgoingMessage)
        case canNotSendOpenMessage
    }
}
