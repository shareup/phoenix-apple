import Foundation
import WebSocketProtocol

public enum RawOutgoingMessage: CustomStringConvertible, Hashable {
    case binary(Data)
    case text(String)

    public var description: String {
        switch self {
        case let .binary(data): return String(data: data, encoding: .utf8) ?? ""
        case let .text(text): return text
        }
    }
}

public struct OutgoingMessage: CustomDebugStringConvertible {
    public var joinRef: Ref?
    public var ref: Ref
    public var topic: Topic
    public var event: PhxEvent
    public var payload: Payload
    var sentAt: DispatchTime = DispatchTime.now()
    
    enum Error: Swift.Error {
        case missingChannelJoinRef
    }
    
    init(ref: Ref, topic: Topic, event: PhxEvent, payload: Payload) {
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
    
    public func encoded() throws -> RawOutgoingMessage {
        let array: [Any?] = [
            joinRef?.rawValue,
            ref.rawValue,
            topic,
            event.stringValue,
            payload
        ]
        
        let data = try JSONSerialization.data(withJSONObject: array, options: [])
        return .text(try String(data: data, encoding: .utf8))
    }

    public var debugDescription: String {
        let jr = joinRef?.debugDescription ?? "<nil>"
        let r = ref.debugDescription
        let e = event.stringValue
        let p = "{\(payload.keys.count) values}"
        return "[\(jr),\(r),\"\(topic)\",\"\(e)\",\(p)]"
    }
}
