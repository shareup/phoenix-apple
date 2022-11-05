import Foundation
import WebSocket

public struct Push: Identifiable, Hashable, CustomStringConvertible, Sendable {
    public var id: Ref { ref }

    public let joinRef: Ref?
    public let ref: Ref
    public let topic: Topic
    public let event: Event
    public let payload: Payload

    init(
        joinRef: Ref?,
        ref: Ref,
        topic: Topic,
        event: Event,
        payload: Payload = [:]
    ) {
        self.joinRef = joinRef
        self.ref = ref
        self.topic = topic
        self.event = event
        self.payload = payload
    }

    public var description: String {
        let _joinRef = joinRef != nil ? "\(joinRef!.rawValue)" : "nil"
        return "\(topic) \(event) \(_joinRef) \(ref.rawValue)"
    }

    public static func encode(_ push: Push) throws -> WebSocketMessage {
        let array: [Any?] = [
            push.joinRef?.rawValue,
            push.ref.rawValue,
            push.topic,
            push.event.stringValue,
            push.payload.jsonDictionary,
        ]

        let data = try JSONSerialization.data(
            withJSONObject: array,
            options: [.sortedKeys]
        )

        guard let encoded = String(data: data, encoding: .utf8)
        else { throw PhoenixError.couldNotEncodePush }
        return .text(encoded)
    }
}
