import Foundation

extension Channel {
    public struct Message {
        let event: String
        let payload: [String: Codable]
        
        init(incomingMessage: IncomingMessage) {
            self.event = incomingMessage.event.stringValue
            self.payload = incomingMessage.payload
        }
    }
}
