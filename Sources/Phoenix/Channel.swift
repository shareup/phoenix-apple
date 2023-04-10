import Foundation
import JSON
import WebSocket

public struct Channel: Identifiable, Sendable {
    public var id: String { topic }
    public let topic: String
    public var join: @Sendable () async throws -> JSON
    public var leave: @Sendable () async throws -> Void
    public var send: @Sendable (String, JSON) async throws -> Void
    public var request: @Sendable (String, JSON) async throws -> JSON
    public var messages: @Sendable () -> AsyncStream<Message>

    public init(
        topic: String,
        join: @escaping @Sendable () async throws -> JSON,
        leave: @escaping @Sendable () async throws -> Void,
        send: @escaping @Sendable (String, JSON) async throws -> Void,
        request: @escaping @Sendable (String, JSON) async throws -> JSON,
        messages: @escaping @Sendable () -> AsyncStream<Message>
    ) {
        self.topic = topic
        self.join = join
        self.leave = leave
        self.send = send
        self.request = request
        self.messages = messages
    }
}

extension Channel {
    static func with(_ phoenix: PhoenixChannel) -> Channel {
        Channel(
            topic: phoenix.topic,
            join: { try await phoenix.join() },
            leave: { try await phoenix.leave() },
            send: { try await phoenix.send($0, payload: $1) },
            request: { try await phoenix.request($0, payload: $1) },
            messages: { phoenix.messages }
        )
    }
}
