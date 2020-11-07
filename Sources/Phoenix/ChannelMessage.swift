extension Channel {
    public struct Message {
        public let event: String
        public let payload: Payload
        
        init(incomingMessage: IncomingMessage) {
            self.event = incomingMessage.event.stringValue
            self.payload = incomingMessage.payload
        }
    }
}
