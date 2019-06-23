import Foundation

extension Phoenix {
    public struct Message {
        public let topic: String
        public let event: Event
        public let payload: Payload
        
        init(topic: String, event: Event, payload: Payload) {
            self.topic = topic
            self.event = event
            self.payload = payload
        }
        
        internal init(from incomingMessage: IncomingMessage) {
            self.init(
                topic: incomingMessage.topic,
                event: incomingMessage.event,
                payload: incomingMessage.payload
            )
        }
    }
}
