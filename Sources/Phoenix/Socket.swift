import Foundation
import JSON
import Synchronized
import WebSocket

public struct Socket: Identifiable, Sendable {
    public let id: Int
    public var connect: @Sendable () async -> Void
    public var disconnect: @Sendable () async -> Void
    public var channel: @Sendable (Topic, JSON) async -> Channel
    public var remove: @Sendable (Topic) async -> Void
    public var removeAll: @Sendable () async -> Void
    public var send: @Sendable (Topic, Event, JSON) async throws -> Void
    public var request: @Sendable (Topic, Event, JSON) async throws -> Message
    public var messages: @Sendable () async -> AsyncStream<Message>

    public init(
        id: Int,
        connect: @escaping @Sendable () async -> Void,
        disconnect: @escaping @Sendable () async -> Void,
        channel: @escaping @Sendable (Topic, JSON) async -> Channel,
        remove: @escaping @Sendable (Topic) async -> Void,
        removeAll: @escaping @Sendable () async -> Void,
        send: @escaping @Sendable (Topic, Event, JSON) async throws -> Void,
        request: @escaping @Sendable (Topic, Event, JSON) async throws -> Message,
        messages: @escaping @Sendable () async -> AsyncStream<Message>
    ) {
        self.id = id
        self.connect = connect
        self.disconnect = disconnect
        self.channel = channel
        self.remove = remove
        self.removeAll = removeAll
        self.send = send
        self.request = request
        self.messages = messages
    }
}

public extension Socket {
    static func system(
        url: @escaping @Sendable () -> URL,
        decoder: @escaping MessageDecoder = Message.decode,
        encoder: @escaping PushEncoder = Push.encode,
        maxMessageSize: Int = 5 * 1024 * 1024
    ) -> Socket {
        let makeWebSocket: MakeWebSocket = { _, url, _, _, _ in
            try await WebSocket.system(
                url: url,
                options: WebSocketOptions(maximumMessageSize: maxMessageSize)
            )
        }

        let phoenix = PhoenixSocket(
            url: url,
            pushEncoder: encoder,
            messageDecoder: decoder,
            makeWebSocket: makeWebSocket
        )

        return Socket(
            id: nextSocketID(),
            connect: { await phoenix.connect() },
            disconnect: { await phoenix.disconnect() },
            channel: { topic, joinPayload in
                Channel.with(
                    await phoenix.channel(
                        topic,
                        joinPayload: joinPayload
                    )
                )
            },
            remove: { await phoenix.remove($0) },
            removeAll: { await phoenix.removeAll() },
            send: { topic, event, payload in
                let push = Push(topic: topic, event: event, payload: payload)
                try await phoenix.send(push)
            },
            request: { topic, event, payload in
                let push = Push(topic: topic, event: event, payload: payload)
                return try await phoenix.request(push)
            },
            messages: { phoenix.messages }
        )
    }
}

private let socketID = Locked(0)
@Sendable
private func nextSocketID() -> Int {
    socketID.access { id in
        id += 1
        return id
    }
}
