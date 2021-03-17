public extension Channel {
    struct Message {
        public let event: String
        public let payload: Payload

        public init(event: String, payload: Payload) {
            self.event = event
            self.payload = payload
        }

        init(incomingMessage: IncomingMessage) {
            event = incomingMessage.event.stringValue
            payload = incomingMessage.payload
        }
    }
}
