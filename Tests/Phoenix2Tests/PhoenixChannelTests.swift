import AsyncExtensions
import AsyncTestExtensions
import Combine
@testable import Phoenix2
import Synchronized
import WebSocket
import XCTest

final class PhoenixChannelTests: XCTestCase {
    private let url = URL(string: "ws://0.0.0.0:4003/socket")!

    private var onOpen: AsyncExtensions.Future<Void>!
    private var onClose: AsyncExtensions.Future<WebSocketClose>!

    private var sendSubject: PassthroughSubject<WebSocketMessage, Never>!
    private var receiveSubject: PassthroughSubject<WebSocketMessage, Never>!

    override func setUp() async throws {
        try await super.setUp()

        onOpen = .init()
        onClose = .init()

        sendSubject = .init()
        receiveSubject = .init()
    }

    override func tearDown() async throws {
        try await super.tearDown()

        onOpen = nil
        onClose = nil
        sendSubject = nil
        receiveSubject = nil
    }

    // MARK: "constructor"

    // NOTE: We do not allow updating the join parameters.

    func testChannelInit() async throws {
        let channel = makeChannel(
            joinPayload: ["one": "two"],
            PhoenixSocket(url: url) { _, _, _, _, _ in
                self.makeWebSocket()
            }
        )

        XCTAssertTrue(channel.isUnjoined)
        XCTAssertEqual("topic", channel.topic)
        XCTAssertEqual(
            ["one": "two"],
            channel.joinPayload.jsonDictionary as? [String: String]
        )
    }

    func testCreatesCorrectJoinPush() async throws {
        try await withSocket { socket in
            await socket.connect()

            let channel = self.makeChannel(joinPayload: ["one": "two"], socket)

            let didSendJoin = Locked(false)
            let task = Task {
                let msg = try await self.nextOutoingMessage()
                XCTAssertEqual("topic", msg.topic)
                XCTAssertEqual("phx_join", msg.event.stringValue)
                XCTAssertEqual(["one": "two"], msg.payload)
                didSendJoin.access { $0 = true }
            }

            // The join will fail because we don't reply, but it
            // doesn't matter because we only are testing the
            // content of the join message.
            async let _ = channel.join()
            try await task.value
            XCTAssertTrue(didSendJoin.access { $0 })
        }
    }

    // MARK: "join"

    func testSetsStateToJoining() async throws {
        try await withSocket { socket in
            await socket.connect()
            let channel = self.makeChannel(socket)
            let task = Task { try await channel.join() }
            await AssertTrueEventually(channel.isJoining)
            task.cancel()
        }
    }

    // NOTE: We do not have the concept of didJoin in our
    // channels because we do not tear down and recreate
    // new channels in the socket when someone calls
    // `PhoenixSocket.channel()`. Instead, we return the
    // existing channel. Therefore, since it's normal for
    // the caller to immediately call `channel.join()` after
    // getting one from the socket, it doesn't make sense
    // to throw an error if it's already been joined. So, if
    // the channel is already joined, we just return the
    // received channel reply payload.
    func testDoesNotThrowWhenAttemptingToJoinMultipleTimes() async throws {
        try await withSocket { socket in
            await socket.connect()
            let channel = self.makeChannel(socket)

            Task {
                let msg = try await self.nextOutoingMessage()
                XCTAssertEqual("topic", msg.topic)
                XCTAssertEqual(.join, msg.event)
                try self.sendJoinReply(for: msg, payload: ["one": "two"])
            }

            await withThrowingTaskGroup(of: Payload.self) { group in
                // Make sure the listener starts first
                await self.wait()

                group.addTask { try await channel.join() }
                group.addTask { try await channel.join() }

                var payloads: [Payload?] = []

                do {
                    for try await payload in group {
                        payloads.append(payload)
                        if payloads.count == 2 { break }
                    }
                } catch {
                    XCTFail("Joins should have succeeded")
                }

                XCTAssertEqual(2, payloads.count)
                XCTAssertEqual(["one": "two"], payloads.first)
                XCTAssertEqual(["one": "two"], payloads.last)
            }
        }
    }

    func testTriggersSocketPushWithJoinPayload() async throws {
        try await withSocket { socket in
            await socket.connect()
            let channel = self.makeChannel(
                joinPayload: ["one": "two"],
                socket
            )
            let task = Task {
                let msg = try await self.nextOutoingMessage()
                XCTAssertEqual("topic", msg.topic)
                XCTAssertEqual(.join, msg.event)
                XCTAssertEqual(["one": "two"], msg.payload)
            }
            async let _ = channel.join()
            try await task.value
        }
    }

    func testTimeoutOnJoinPush() async throws {
        try await withSocket { socket in
            await socket.connect()
            let channel = self.makeChannel(socket)
            var didTimeout = false
            let start = Date()
            do {
                try await channel.join(timeout: 0.001)
            } catch is TimeoutError {
                didTimeout = true
                // CI machines can be slow, so we add extra time
                XCTAssertLessThan(Date().timeIntervalSince(start), 0.5)
            }
            XCTAssertTrue(didTimeout)
        }
    }

    // MARK: "timeout behavior"

    func testJoinSucceedsBeforeTimeout() async throws {
        try await withAutoConnectAndJoinSocket { socket in
            let channel = self.makeChannel(socket)
            try await channel.join(timeout: 1)
            await AssertTrueEventually(channel.isJoined)
        }
    }

    func testRetriesJoinWithBackoffAfterTimeout() async throws {
        try await withSocket { socket in
            await socket.connect()
            let channel = self.makeChannel(
                rejoinDelay: [0, 0.001, 0.1, 100],
                socket
            )

            let start = Date()

            Task {
                var attempt = 0
                for await msg in self.sendSubject.values {
                    guard let message = try? Message.decode(msg),
                          case .join = message.event
                    else { return XCTFail() }

                    defer { attempt += 1 }

                    switch attempt {
                    case 0:
                        break

                    case 1:
                        break

                    case 2:
                        try self.sendJoinReply(for: message)

                    default:
                        XCTFail()
                    }
                }
            }

            Task {
                await self.wait()
                try await channel.join(timeout: 0.01)
            }

            await AssertTrueEventually(channel.isJoined)

            XCTAssertGreaterThanOrEqual(
                Date().timeIntervalSince(start),
                0.11
            )
        }
    }

}

private extension PhoenixChannelTests {
    func makeWebSocket() -> WebSocket {
        WebSocket(
            id: .random(in: 1 ... 1_000_000_000),
            open: { self.onOpen.resolve() },
            close: { code, _ in self.onClose.resolve(.init(code, nil)) },
            send: { self.sendSubject.send($0) },
            messagesPublisher: { self.receiveSubject.eraseToAnyPublisher() }
        )
    }

    func withSocket(
        timeout: TimeInterval = 10,
        heartbeatInterval: TimeInterval = 30,
        block: @escaping (PhoenixSocket) async throws -> Void
    ) async throws {
        let makeWS: MakeWebSocket = { _, _, _, _, _ in self.makeWebSocket() }

        let socket = PhoenixSocket(
            url: url,
            timeout: timeout,
            heartbeatInterval: heartbeatInterval,
            makeWebSocket: makeWS
        )

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await Task.sleep(nanoseconds: 2 * NSEC_PER_SEC)
                if !Task.isCancelled { throw TimeoutError() }
            }
            group.addTask { try await block(socket) }

            try await group.next()
            group.cancelAll()
        }

        for channel in await socket.channels.values {
            try? await channel.leave(timeout: 0.000001)
        }
        await socket.disconnect(timeout: 0.000001)
    }

    func withAutoConnectAndJoinSocket(
        timeout: TimeInterval = 10,
        heartbeatInterval: TimeInterval = 30,
        block: @escaping (PhoenixSocket) async throws -> Void
    ) async throws {
        let makeWS: MakeWebSocket = { _, _, _, _, _ in self.makeWebSocket() }

        let socket = PhoenixSocket(
            url: url,
            timeout: timeout,
            heartbeatInterval: heartbeatInterval,
            makeWebSocket: makeWS
        )

        await socket.connect()

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for await msg in self.sendSubject.values {
                    guard let message = try? Message.decode(msg),
                          message.event == .join,
                          message.ref != nil
                    else { continue }
                    try self.sendJoinReply(for: message)
                }
            }

            group.addTask {
                await self.wait()
                try await Task.sleep(nanoseconds: 2 * NSEC_PER_SEC)
                if !Task.isCancelled { throw TimeoutError() }
            }

            group.addTask {
                await self.wait()
                try await block(socket)
            }

            try await group.next()
            group.cancelAll()
        }

        for channel in await socket.channels.values {
            try? await channel.leave(timeout: 0.000001)
        }
        await socket.disconnect(timeout: 0.000001)
    }

    func makeChannel(
        topic: String = "topic",
        rejoinDelay: [TimeInterval] = [0, 10],
        joinPayload: Payload = [:],
        _ socket: PhoenixSocket
    ) -> PhoenixChannel {
        PhoenixChannel(
            topic: topic,
            joinPayload: joinPayload,
            rejoinDelay: rejoinDelay,
            socket: socket
        )
    }

    func nextOutoingMessage() async throws -> Message {
        for await message in sendSubject.values {
            return try Message.decode(message)
        }
        throw CancellationError()
    }

    func sendJoinReply(
        for message: Message,
        payload: Payload = [:]
    ) throws {
        let reply = String(
            data: try JSONSerialization.data(
                withJSONObject: [
                    message.ref!.rawValue,
                    message.ref!.rawValue,
                    message.topic,
                    "phx_reply",
                    [
                        "status": "ok",
                        "response": payload.jsonDictionary,
                    ] as [String: Any],
                ] as [Any]
            ),
            encoding: .utf8
        )!

        receiveSubject.send(.text(reply))
    }

    func wait() async {
        for _ in 0 ..< 100 {
            await Task.yield()
        }
    }
}
