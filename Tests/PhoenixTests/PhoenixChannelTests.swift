import AsyncExtensions
import AsyncTestExtensions
import Combine
@testable import Phoenix
import Synchronized
import WebSocket
import XCTest

final class PhoenixChannelTests: XCTestCase {
    private let url = URL(string: "ws://0.0.0.0:4003/socket")!

    private var sendSubject: PassthroughSubject<WebSocketMessage, Never>!
    private var receiveSubject: PassthroughSubject<WebSocketMessage, Never>!

    override func setUp() async throws {
        try await super.setUp()

        sendSubject = .init()
        receiveSubject = .init()
    }

    override func tearDown() async throws {
        try await super.tearDown()

        sendSubject.send(completion: .finished)
        receiveSubject.send(completion: .finished)
    }

    // MARK: "constructor"

    // NOTE: We do not allow updating the join parameters.

    func testChannelInit() async throws {
        let channel = await makeChannel(
            joinPayload: ["one": "two"],
            rejoinDelay: [10],
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

            let channel = await self.makeChannel(
                joinPayload: ["one": "two"],
                socket
            )

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
            async let _ = channel.join(timeout: 0.01)
            try await task.value
            XCTAssertTrue(didSendJoin.access { $0 })
        }
    }

    // MARK: "join"

    func testSetsStateToJoining() async throws {
        try await withSocket { socket in
            await socket.connect()
            let channel = await self.makeChannel(socket)
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
            let channel = await self.makeChannel(socket)

            Task {
                let msg = try await self.nextOutoingMessage()
                XCTAssertEqual("topic", msg.topic)
                XCTAssertEqual(.join, msg.event)
                try self.sendReply(for: msg, payload: ["one": "two"])
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
            let channel = await self.makeChannel(
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
            let channel = await self.makeChannel(socket)
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
            let channel = await self.makeChannel(socket)
            try await channel.join(timeout: 1)
            await AssertTrueEventually(channel.isJoined)
        }
    }

    func testRetriesJoinWithBackoffAfterTimeout() async throws {
        try await withSocket { socket in
            await socket.connect()
            let channel = await self.makeChannel(
                rejoinDelay: [0, 0.001, 0.1, 100],
                socket
            )

            let start = Date()

            Task {
                var attempt = 0
                for await msg in self.outgoingMessages {
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
                        try self.sendReply(for: message)

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

    func testJoinsAfterSocketOpenAndJoinDelays() async throws {
        let openFuture = AsyncExtensions.Future<Void>()
        let canJoin = Locked(false)
        let didJoin = Locked(false)

        let ws = makeDelayedWebSocket(
            openDelay: { try? await openFuture.value }
        )

        try await withSocket(webSocket: ws) { socket in
            await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { await socket.connect() }

                group.addTask {
                    for await msg in self.outgoingMessages {
                        guard let message = try? Message.decode(msg),
                              case .join = message.event,
                              canJoin.access({ $0 })
                        else { continue }

                        try self.sendReply(for: message)
                    }
                }

                group.addTask {
                    await self.wait()

                    let channel = await self.makeChannel(
                        rejoinDelay: [0, 0.02],
                        socket
                    )

                    do {
                        try await channel.join(timeout: 0.01)
                    } catch is TimeoutError {
                        // This is different from the PhoenixJS test.
                        // Our channel errors on timeout, but then we
                        // switch to `joining` while waiting for the join
                        // delay to pass. We do this to prevent races.
                        XCTAssertTrue(channel.isErrored || channel.isJoining)

                        openFuture.resolve()

                        try? await Task.sleep(nanoseconds: NSEC_PER_MSEC * 15)
                        canJoin.access { $0 = true }

                        await AssertTrueEventually(channel.isJoined)
                        didJoin.access { $0 = true }
                    } catch is CancellationError {
                    } catch {
                        XCTFail("Should have timed out")
                    }
                }

                await AssertTrueEventually(didJoin.access { $0 })
                group.cancelAll()
            }
        }

        XCTAssertTrue(didJoin.access { $0 })
    }

    func testOpensAfterSocketOpenDelay() async throws {
        let openFuture = AsyncExtensions.Future<Void>()
        let canJoin = Locked(false)
        let didJoin = Locked(false)

        let ws = makeDelayedWebSocket(
            openDelay: { try? await openFuture.value }
        )

        try await withSocket(webSocket: ws) { socket in
            await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { await socket.connect() }

                group.addTask {
                    for await msg in self.outgoingMessages {
                        guard let message = try? Message.decode(msg),
                              case .join = message.event,
                              canJoin.access({ $0 })
                        else { continue }

                        try self.sendReply(for: message)
                    }
                }

                group.addTask {
                    let channel = await self.makeChannel(
                        rejoinDelay: [0, 0.02],
                        socket
                    )

                    do {
                        try await channel.join(timeout: 0.01)
                    } catch is TimeoutError {
                        try? await Task.sleep(nanoseconds: NSEC_PER_MSEC * 30)

                        openFuture.resolve()
                        canJoin.access { $0 = true }

                        await AssertTrueEventually(channel.isJoined)
                        didJoin.access { $0 = true }
                    } catch is CancellationError {
                    } catch {
                        XCTFail("Should have timed out")
                    }
                }

                await AssertTrueEventually(didJoin.access { $0 })
                group.cancelAll()
            }
        }

        XCTAssertTrue(didJoin.access { $0 })
    }

    // MARK: "joinPush"

    // NOTE: This test consolidates many smaller, focused tests
    // in the PhoenixJS test suite.
    func testReceivesSuccessfulJoinResponse() async throws {
        try await withSocket { socket in
            await socket.connect()

            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    for await msg in self.outgoingMessages {
                        guard let message = try? Message.decode(msg),
                              case .join = message.event
                        else { continue }

                        // Only replies to one join message, which
                        // let's us test that the second call to
                        // join() reuses the initial response.
                        return try self.sendReply(
                            for: message,
                            payload: ["worked": true]
                        )
                    }
                }

                let didJoin1 = AsyncExtensions.Future<Void>()
                let didJoin2 = AsyncExtensions.Future<Void>()

                let channel = await self.makeChannel(socket)

                group.addTask {
                    let payload = try await channel.join(timeout: 1)
                    XCTAssertEqual(["worked": true], payload)
                    await AssertTrueEventually(channel.isJoined)
                    didJoin1.resolve()
                }

                group.addTask {
                    try await didJoin1.value
                    XCTAssertTrue(channel.isJoined)
                    let payload = try await channel.join(timeout: 0.01)
                    XCTAssertEqual(["worked": true], payload)
                    didJoin2.resolve()
                }

                try await didJoin2.value
                XCTAssertTrue(channel.isJoined)
            }
        }
    }

    func testBufferedMessagesAllGetSentAfterSuccessfulJoin() async throws {
        try await withSocket { socket in
            await socket.connect()

            let sentMessages = Locked<[Message]>([])

            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    for await msg in self.outgoingMessages {
                        let message = try Message.decode(msg)
                        try self.sendReply(for: message)
                        let count = sentMessages.access { sentMessages in
                            sentMessages.append(message)
                            return sentMessages.count
                        }
                        if count == 4 { break }
                    }
                }

                let channel = await self.makeChannel(socket)

                for event in ["one", "two", "three"] {
                    group.addTask {
                        do {
                            try await channel.push(event)
                        } catch {
                            XCTFail("Push should have succeeded instead of \(error)")
                        }
                    }
                }

                try await Task.sleep(nanoseconds: NSEC_PER_MSEC * 10)
                try await channel.join()

                try await group.waitForAll()
            }

            XCTAssertEqual(4, sentMessages.access { $0.count })
            XCTAssertEqual(.join, sentMessages.access { $0[0].event })
        }
    }

    func testRejoinsAfterJoinTimeout() async throws {
        try await withSocket { socket in
            await socket.connect()

            let channel = await self.makeChannel(
                rejoinDelay: [0.01],
                socket
            )

            let didJoin = Locked(false)

            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    var receivedJoin = false
                    for await msg in self.outgoingMessages {
                        let message = try Message.decode(msg)

                        guard message.event == .join else { continue }

                        if receivedJoin {
                            didJoin.access { $0 = true }
                            break
                        } else {
                            receivedJoin = true
                            await Task.yield()
                        }
                    }
                    XCTAssertTrue(receivedJoin)
                }

                group.addTask {
                    do { try await channel.join(timeout: 0.01) }
                    catch is TimeoutError {}
                    catch {
                        XCTFail("Should not have received \(error)")
                    }
                }

                try await group.waitForAll()

                XCTAssertTrue(didJoin.access { $0 })
            }
        }
    }
}

private extension PhoenixChannelTests {
    func makeWebSocket() -> WebSocket {
        WebSocket(
            id: .random(in: 1 ... 1_000_000_000),
            open: {},
            close: { _, _ in },
            send: { self.sendSubject.send($0) },
            messagesPublisher: { self.receiveSubject.eraseToAnyPublisher() }
        )
    }

    func makeDelayedWebSocket(
        openDelay: (() async -> Void)? = nil,
        closeDelay: (() async -> Void)? = nil
    ) -> WebSocket {
        WebSocket(
            id: .random(in: 1 ... 1_000_000_000),
            open: { if let openDelay { await openDelay() } },
            close: { _, _ in if let closeDelay { await closeDelay() } },
            send: { self.sendSubject.send($0) },
            messagesPublisher: { self.receiveSubject.eraseToAnyPublisher() }
        )
    }

    func withSocket(
        webSocket: WebSocket? = nil,
        timeout: TimeInterval = 10,
        heartbeatInterval: TimeInterval = 30,
        block: @escaping (PhoenixSocket) async throws -> Void
    ) async throws {
        let makeWS: MakeWebSocket = { _, _, _, _, _ in
            webSocket ?? self.makeWebSocket()
        }

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
        webSocket: WebSocket? = nil,
        timeout: TimeInterval = 10,
        heartbeatInterval: TimeInterval = 30,
        block: @escaping (PhoenixSocket) async throws -> Void
    ) async throws {
        let makeWS: MakeWebSocket = { _, _, _, _, _ in
            webSocket ?? self.makeWebSocket()
        }

        let socket = PhoenixSocket(
            url: url,
            timeout: timeout,
            heartbeatInterval: heartbeatInterval,
            makeWebSocket: makeWS
        )

        await socket.connect()

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for await msg in self.outgoingMessages {
                    guard let message = try? Message.decode(msg),
                          message.event == .join,
                          message.ref != nil
                    else { continue }
                    try self.sendReply(for: message)
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
        joinPayload: Payload = [:],
        rejoinDelay: [TimeInterval] = [0, 10],
        _ socket: PhoenixSocket
    ) async -> PhoenixChannel {
        await socket.channel(
            topic,
            joinPayload: joinPayload,
            rejoinDelay: rejoinDelay
        )
    }

    var outgoingMessages: AsyncStream<WebSocketMessage> {
        sendSubject.allValues
    }

    func nextOutoingMessage() async throws -> Message {
        for await message in outgoingMessages {
            return try Message.decode(message)
        }
        throw CancellationError()
    }

    func sendReply(
        for message: Message,
        payload: Payload = [:]
    ) throws {
        let joinRef = message.event == .join ? message.ref! : message.joinRef!
        let reply = String(
            data: try JSONSerialization.data(
                withJSONObject: [
                    joinRef.rawValue,
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
