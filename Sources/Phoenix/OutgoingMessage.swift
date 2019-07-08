import Foundation

struct OutgoingMessage {
    let joinRef: Ref?
    let ref: Ref
    let topic: String
    let event: Event
    let payload: Payload
    let sentAt: Date = Date()
    
    init(_ push: Channel.Push, ref: Ref) {
        self.joinRef = push.channel.joinRef
        self.ref = ref
        self.topic = push.channel.topic
        self.event = push.event
        self.payload = push.payload
    }
    
    init(_ push: Socket.Push, ref: Ref) {
        self.joinRef = nil
        self.ref = ref
        self.topic = push.topic
        self.event = push.event
        self.payload = push.payload
    }
    
    func encoded() throws -> Data {
        let array: [Any?] = [
            joinRef?.rawValue,
            ref.rawValue,
            topic,
            event.stringValue,
            payload
        ]
        
        return try JSONSerialization.data(withJSONObject: array, options: [])
    }
}
