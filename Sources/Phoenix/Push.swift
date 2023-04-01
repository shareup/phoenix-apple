import Foundation
import JSON
import Synchronized
import WebSocket

public final class Push: Hashable, CustomStringConvertible, Sendable {
    public var joinRef: Ref? { state.access { $0.joinRef } }
    public var ref: Ref? { state.access { $0.ref } }

    public let topic: Topic
    public let event: Event
    public let payload: JSON
    public let timeout: Date

    private let state = Locked(State())

    public init(
        topic: Topic,
        event: Event,
        payload: JSON = [:],
        timeout: Date = Date(timeIntervalSinceNow: 5)
    ) {
        self.topic = topic
        self.event = event
        self.payload = payload
        self.timeout = timeout
    }

    public var description: String {
        let (joinRef, ref) = state.access { ($0.joinRef, $0.ref) }
        let _joinRef = joinRef != nil ? "\(joinRef!.rawValue)" : "nil"
        let _ref = ref != nil ? "\(ref!.rawValue)" : "nil"
        return "[\(topic), \(event), \(_joinRef), \(_ref)]"
    }

    func prepareToSend(ref: Ref, joinRef: Ref? = nil) {
        state.access { $0.prepareToSend(ref: ref, joinRef: joinRef) }
    }

    func reset() {
        state.access { $0.reset() }
    }

    @Sendable
    public static func encode(_ push: Push) throws -> WebSocketMessage {
        let (joinRef, ref) = push.state.access { state in
            precondition(
                state.ref != nil,
                "Call preapreToSend() before encoding"
            )

            return (state.joinRef, state.ref!)
        }

        let array: [Any?] = [
            joinRef?.rawValue,
            ref.rawValue,
            push.topic,
            push.event.stringValue,
            push.payload.dictionaryValue,
        ]

        let data = try JSONSerialization.data(
            withJSONObject: array,
            options: [.sortedKeys]
        )

        guard let encoded = String(data: data, encoding: .utf8)
        else { throw PhoenixError.couldNotEncodePush }
        return .text(encoded)
    }

    public static func == (lhs: Push, rhs: Push) -> Bool {
        ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}

private struct State: Hashable {
    private(set) var joinRef: Ref?
    private(set) var ref: Ref?

    mutating func prepareToSend(ref: Ref, joinRef: Ref?) {
        self.ref = ref
        self.joinRef = joinRef
    }

    mutating func reset() {
        ref = nil
        joinRef = nil
    }
}
