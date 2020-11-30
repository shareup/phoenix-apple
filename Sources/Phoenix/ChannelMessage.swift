extension Channel {
    public struct Message {
        public let event: String
        public let payload: Payload

        public init(event: String, payload: Payload) {
            self.event = event
            self.payload = payload
        }
        
        init(incomingMessage: IncomingMessage) {
            self.event = incomingMessage.event.stringValue
            self.payload = incomingMessage.payload
        }
    }
}
