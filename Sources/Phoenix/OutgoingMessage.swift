import Foundation

struct OutgoingMessage {
    let joinRef: Ref?
    let ref: Ref
    let topic: String
    let event: PhxEvent
    let payload: Payload
    let sentAt: Date = Date()
    
    enum Error: Swift.Error {
        case missingChannelJoinRef
    }
    
    init(ref: Ref, topic: String, event: PhxEvent, payload: Payload) {
        self.joinRef = nil
        self.ref = ref
        self.topic = topic
        self.event = event
        self.payload = payload
    }
    
    init(_ push: Channel.Push, ref: Ref, joinRef: Ref) {
        if push.channel.joinRef != joinRef {
            preconditionFailure("joinRef should match the channel's joinRef")
        }
        
        self.joinRef = joinRef
        self.ref = ref
        self.topic = push.channel.topic
        self.event = push.event
        self.payload = push.payload
    }
    
    init(_ push: Socket.Push, ref: Ref, joinRef: Ref? = nil) {
        self.joinRef = joinRef
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
