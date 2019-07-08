import Foundation

extension Channel {
    public struct Message {
        let event: String
        let payload: Payload
        
        init(incomingMessage: IncomingMessage) {
            self.event = incomingMessage.event.stringValue
            self.payload = incomingMessage.payload
        }
    }
}
