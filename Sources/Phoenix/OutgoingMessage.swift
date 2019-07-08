import Foundation

struct OutgoingMessage {
    let joinRef: Ref?
    let ref: Ref
    let topic: String
    let event: Event
    let payload: [String: Codable]
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
}

extension OutgoingMessage: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(joinRef)
        try container.encode(ref)
        try container.encode(topic)
        try container.encode(event)
        try container.encode(try payload.validPayload())
    }
}
