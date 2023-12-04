import AsyncExtensions
import AsyncTestExtensions
import Combine
import JSON
@testable import Phoenix
import Synchronized
import WebSocket
import XCTest

// NOTE: Names in quotation marks below correspond to groups of tests
// delimited by `describe("some name", {})` blocks in Phoenix JS'
// test suite, which can be found here:
// https://github.com/phoenixframework/phoenix/blob/v1.7.1/assets/test/socket_test.js
//
// Many of the test in the Phoenix framework's JavaScript client tests
// do not apply to our socket or overlap other tests. We skip those tests.

final class PhoenixSocketTests: XCTestCase {
    private let url = { @Sendable in URL(string: "ws://0.0.0.0:4003/socket")! }

    private var sendSubject: PassthroughSubject<WebSocketMessage, Never>!
    private var receiveSubject: PassthroughSubject<WebSocketMessage, Never>!

    override func setUp() {
        super.setUp()
        sendSubject = PassthroughSubject()
        receiveSubject = PassthroughSubject()
    }

    override func tearDown() {
        sendSubject.send(completion: .finished)
        receiveSubject.send(completion: .finished)
        super.tearDown()
    }

    // MARK: "constructor" and "endpointURL"

    func testSocketInitWithDefaults() async throws {
        let socket = PhoenixSocket(
            url: url,
            makeWebSocket: makeFakeWebSocket
        )

        let url = socket.url
        XCTAssertEqual(url().path, "/socket/websocket")
        XCTAssertEqual(url().query, "vsn=2.0.0")

        XCTAssertEqual(10 * NSEC_PER_SEC, socket.timeout)
        XCTAssertEqual(30 * NSEC_PER_SEC, socket.heartbeatInterval)
    }

    func testSocketInitWithCustomValues() async throws {
        let socket = PhoenixSocket(
            url: url,
            timeout: 12,
            heartbeatInterval: 29,
            makeWebSocket: makeFakeWebSocket
        )

        let url = socket.url
        XCTAssertEqual(url().path, "/socket/websocket")
        XCTAssertEqual(url().query, "vsn=2.0.0")

        XCTAssertEqual(12 * NSEC_PER_SEC, socket.timeout)
        XCTAssertEqual(29 * NSEC_PER_SEC, socket.heartbeatInterval)
    }

    // MARK: "connect with WebSocket"

    func testConnectsToCorrectURL() async throws {
        let createdWebSocket = Locked(false)
        let expected = URL(string: "ws://0.0.0.0:4003/socket/websocket?vsn=2.0.0")!

        let makeWS: MakeWebSocket = { _, url, _, _, _ in
            createdWebSocket.access { $0 = true }
            XCTAssertEqual(expected, url)
            return self.fake()
        }

        let socket = PhoenixSocket(url: url, makeWebSocket: makeWS)
        await socket.connect()

        XCTAssertTrue(createdWebSocket.access { $0 })
    }

    func testOpenStateCallbackIsCalled() async throws {
        var opens = 0
        let onOpen: () -> Void = { opens += 1 }

        try await withWebSocket(fake(), onOpen: onOpen) { socket in
            await socket.connect()
        }

        XCTAssertEqual(1, opens)
    }

    func testCallingConnectWhileConnectedIsNoop() async throws {
        let socket = PhoenixSocket(url: url, makeWebSocket: makeFakeWebSocket)

        await socket.connect()
        let id1 = await socket.webSocket?.id
        XCTAssertNotNil(id1)

        await socket.connect()
        let id2 = await socket.webSocket?.id
        XCTAssertEqual(id1, id2)
    }

    // MARK: "disconnect"

    func testDisconnectDestroysWebSocket() async throws {
        let socket = PhoenixSocket(url: url, makeWebSocket: makeFakeWebSocket)

        await socket.connect()
        await AssertNotNil(await socket.webSocket?.id)

        await socket.disconnect()
        await AssertNil(await socket.webSocket?.id)
    }

    func testCloseStateCallbackIsCalled() async throws {
        let closes = Locked(0)
        let onPhoenixClose: () -> Void = { closes.access { $0 += 1 } }
        let onClose: WebSocketOnClose = { (close: WebSocketClose) in
            closes.access { $0 += 1 }
            XCTAssertEqual(.normalClosure, close.code)
            XCTAssertTrue(close.isNormal)
            XCTAssertNil(close.reason)
        }

        try await withWebSocket(
            fake(onOpen: {}, onClose: onClose),
            onClose: onPhoenixClose
        ) { socket in
            await socket.connect()
            await socket.disconnect()
        }

        XCTAssertEqual(2, closes.access { $0 })
    }

    func testDisconnectIsNoopWhenNotConnected() async throws {
        let closes = Locked(0)
        let onPhoenixClose: () -> Void = { closes.access { $0 += 1 } }
        let onClose: WebSocketOnClose = { _ in closes.access { $0 += 1 } }

        try await withWebSocket(
            fake(onOpen: {}, onClose: onClose),
            onClose: onPhoenixClose
        ) { socket in
            await socket.disconnect()
            await socket.disconnect()
            await socket.disconnect()
        }

        //
        XCTAssertEqual(0, closes.access { $0 })
    }

    // MARK: "connectionState"

    func testConnectionStateIsClosedInitially() async throws {
        try await withWebSocket(fake()) { socket in
            await AssertTrue(socket.connectionState.isClosed)
        }
    }

    func testConnectionStateIsConnectingWhenConnecting() async throws {
        let didChangeToConnecting = future(timeout: 2)
        let socket = PhoenixSocket(
            url: url,
            makeWebSocket: makeFakeWebSocket
        )
        let sub = socket.onConnectionStateChange.sink { state in
            guard state.isConnecting else { return }
            didChangeToConnecting.resolve()
        }
        await socket.connect()
        try await didChangeToConnecting.value
        sub.cancel()
    }

    func testConnectionStateIsOpenAfterConnecting() async throws {
        try await withWebSocket(fake()) { socket in
            await socket.connect()
            await AssertTrue(socket.connectionState.isOpen)
        }
    }

    func testConnectionStateIsClosingWhenDisconnecting() async throws {
        var didChangeToClosing = false
        let socket = PhoenixSocket(url: url, makeWebSocket: makeFakeWebSocket)

        let sub = socket.onConnectionStateChange.sink { state in
            guard state.isClosing else { return }
            guard !didChangeToClosing
            else { return XCTFail("Should have only changed to closing once") }
            didChangeToClosing = true
        }

        await socket.connect()
        await socket.disconnect()
        XCTAssertTrue(didChangeToClosing)
        sub.cancel()
    }

    func testConnectionStateIsClosedAfterDisconnecting() async throws {
        try await withWebSocket(fake()) { socket in
            await socket.connect()
            await AssertTrue(socket.connectionState.isOpen)

            await socket.disconnect()
            await AssertTrue(socket.connectionState.isClosed)
        }
    }

    func testIsConnectedPublisher() async throws {
        let didConnected = future(timeout: 2)
        let didDisconnected = future(timeout: 2)

        let socket = PhoenixSocket(
            url: url,
            makeWebSocket: makeFakeWebSocket
        )

        let sub = socket.isConnected
            .sink { isConnected in
                if isConnected {
                    didConnected.resolve()
                } else {
                    didDisconnected.resolve()
                }
            }

        await socket.connect()

        try await didConnected.value

        await socket.disconnect()

        try await didDisconnected.value

        sub.cancel()
    }

    // MARK: "channel"

    func testCreateChannelWithTopicAndPayload() async throws {
        try await withWebSocket(fake()) { socket in
            let channel = await socket.channel("topic", joinPayload: ["one": "two"])
            XCTAssertEqual("topic", channel.topic)
            XCTAssertEqual(["one": "two"], channel.joinPayload)
        }
    }

    func testCreatingChannelsAddsItToChannelsDictionary() async throws {
        try await withWebSocket(fake()) { socket in
            _ = await socket.channel("topic", joinPayload: ["one": "two"])

            let channels = await socket.channels
            XCTAssertEqual(1, channels.count)
            let channel = try XCTUnwrap(channels["topic"])

            XCTAssertEqual("topic", channel.topic)
            XCTAssertEqual(["one": "two"], channel.joinPayload)
        }
    }

    // NOTE: This behavior is different from PhoenixJS', which is
    // leaving the original channel and joining the newly-created
    // one.
    func testCallingChannelTwiceWithSameTopicReturnsSameChannel() async throws {
        try await withWebSocket(fake()) { socket in
            let channel1 = await socket.channel(
                "topic",
                joinPayload: ["one": "two"]
            )

            let channel2 = await socket.channel(
                "topic",
                joinPayload: ["one": "two"]
            )

            XCTAssertEqual(ObjectIdentifier(channel1), ObjectIdentifier(channel2))
        }
    }

    // MARK: "remove"

    func testRemoveRemovesChannelFromChannelsDictionary() async throws {
        try await withWebSocket(fake()) { socket in
            let channel1 = await socket.channel("topic-1")
            let channel2 = await socket.channel("topic-2")
            await AssertEqual(2, await socket.channels.count)

            await socket.remove(channel1)

            await AssertEqual(1, await socket.channels.count)

            let channel = await socket.channels.first?.value
            XCTAssertEqual(channel2.topic, channel?.topic)
        }
    }

    // MARK: "push"

    func testPushSendsDataToWebSocketWhenConnected() async throws {
        var sent = [WebSocketMessage]()

        let ws: WebSocket = fake(onSend: { sent.append($0) })
        try await withWebSocket(ws) { socket in
            await socket.connect()
            try await socket.send(self.push1)
            await AssertEqualEventually(self.encodedPush1, sent.first)
        }
    }

    func testBuffersDataWhenWebSocketIsNotConnected() async throws {
        let canSend = Locked(false)
        let didSend = Locked(false)

        let ws: WebSocket = fake(
            onSend: { message in
                if canSend.access({ $0 }) {
                    XCTAssertEqual(self.encodedPush1, message)
                    didSend.access { $0 = true }
                } else {
                    XCTFail("Should not have received a message")
                }
            }
        )

        try await withWebSocket(ws) { socket in
            Task.detached { try await socket.send(self.push1) }
            let sleep = Task {
                try await Task.sleep(nanoseconds: NSEC_PER_MSEC * 50)
                canSend.access { $0 = true }
            }
            try await sleep.value

            await socket.connect()
            await AssertEqualEventually(true, didSend.access { $0 })
        }
    }

    // MARK: "makeRef"

    func testRefNextReturnsNextRef() async throws {
        try await withWebSocket(fake()) { socket in
            await AssertEqual(0, socket.ref)

            let one = await socket.makeRef()
            XCTAssertEqual(1, one)
            await AssertEqual(1, socket.ref)

            let two = await socket.makeRef()
            XCTAssertEqual(2, two)
            await AssertEqual(2, socket.ref)

            let three = await socket.makeRef()
            XCTAssertEqual(3, three)
            await AssertEqual(3, socket.ref)
        }
    }

    func testRefRestartsAtZeroAfterOverflow() throws {
        let ref: Ref = 9_007_199_254_740_991
        XCTAssertEqual(0, ref.next)
    }

    // MARK: "sendHeartbeat"

    func testClosesSocketWhenHeartbeatIsNotAcknowledged() async throws {
        let didClose = Locked(false)

        let ws: WebSocket = fake(
            onClose: { _ in didClose.access { $0 = true } },
            onSend: { _ in }
        )

        try await withWebSocket(ws, timeout: 0.05, heartbeatInterval: 0.05) { socket in
            await socket.connect()
            await AssertTrueEventually((didClose.access { $0 }))
        }
    }

    func testPushesHeartbeatWhenConnected() async throws {
        let didSendHeartbeat = Locked(false)

        let ws: WebSocket = fake(
            onSend: { message in
                switch message {
                case .data:
                    XCTFail()

                case let .text(text):
                    let expected = """
                    [null,1,"phoenix","heartbeat",{}]
                    """
                    XCTAssertEqual(expected, text)
                }
                didSendHeartbeat.access { $0 = true }
            }
        )

        try await withWebSocket(ws, heartbeatInterval: 0.1) { socket in
            await socket.connect()
            await AssertTrueEventually((didSendHeartbeat.access { $0 }))
        }
    }

    func testDoesNotPushHeartbeatWhenNotConnected() async throws {
        let ws: WebSocket = fake(onSend: { _ in XCTFail() })

        try await withWebSocket(ws, heartbeatInterval: 0.05) { _ in
            try await Task.sleep(nanoseconds: NSEC_PER_MSEC * 150)
        }
    }

    // This test is not in Phoenix JavaScript
    func testSendsHeartbeatAgainAfterReceivingReply() async throws {
        let heartbeat1 = future(timeout: 2)
        let heartbeat2 = future(timeout: 2)

        let ws: WebSocket = fake(
            onSend: { message in
                if message == self.heartbeat(ref: 1) {
                    heartbeat1.resolve()
                } else if message == self.heartbeat(ref: 2) {
                    heartbeat2.resolve()
                }
            }
        )

        try await withWebSocket(ws, heartbeatInterval: 0.05) { socket in
            await socket.connect()

            try await heartbeat1.value
            self.receiveSubject.send(self.heartbeatReply(ref: 1))

            try await heartbeat2.value
        }
    }

    // MARK: "flushSendBuffer"

    func testFlushesAllMessagesInBufferWhenConnected() async throws {
        let pushes = Locked(makePushes(5))

        let ws: WebSocket = fake(onSend: { msg in
            _ = pushes.access { $0.remove(matching: msg) }
        })

        try await withWebSocket(ws) { socket in
            Task {
                // Wait until all of the pushes have been added
                try await Task.sleep(nanoseconds: NSEC_PER_MSEC * 50)
                await socket.connect()
            }

            try await withThrowingTaskGroup(of: Void.self) { group in
                pushes
                    .access { $0 }
                    .forEach { push in
                        group.addTask { try await socket.send(push) }
                    }
                try await group.waitForAll()
            }

            XCTAssertTrue(pushes.access { $0.isEmpty })
        }
    }

    // MARK: "onConnOpen"

    func testSendBufferIsFlushedOnConnect() async throws {
        let pushes = Locked(makePushes(2))

        let ws: WebSocket = fake(onSend: { msg in
            XCTAssertTrue(pushes.access { $0.remove(matching: msg) })
        })

        try await withWebSocket(ws) { socket in
            Task {
                // Wait until all of the pushes have been added
                try await Task.sleep(nanoseconds: NSEC_PER_MSEC * 50)
                await socket.connect()
            }

            try await withThrowingTaskGroup(of: Void.self) { group in
                pushes
                    .access { $0 }
                    .forEach { push in
                        group.addTask { try await socket.send(push) }
                    }
                try await group.waitForAll()
            }

            XCTAssertTrue(pushes.access { $0.isEmpty })
        }
    }

    func testReconnectTimerIsResetOnConnect() async throws {
        struct NoInternet: Error {}

        let attempts = Locked(0)

        let ws: WebSocket = fake(
            open: {
                defer { attempts.access { $0 += 1 } }
                if attempts.access({ $0 < 3 }) {
                    throw NoInternet()
                }
            }
        )

        try await withWebSocket(ws) { socket in
            await socket.connect()
            // `reconnectAttempts` only lives on the `.closed`
            // connection state. So, if the socket is open, the
            // `reconnectAttempts` must be zero.
            guard case .open = socket.connectionState
            else { return XCTFail() }
        }
    }

    func testCallsOnOpenCallbackOnConnect() async throws {
        let didCall = Locked(false)
        try await withWebSocket(
            fake(),
            onOpen: { didCall.access { $0 = true } }
        ) { socket in
            await socket.connect()
            XCTAssertTrue(didCall.access { $0 })
        }
    }

    // MARK: "onConnClose"

    // This test differs from the original, which is called
    // "does not schedule reconnectTimer if normal close".
    // We always try to reconnect unless the connection was
    // closed by the client.
    func testDoesNotReconnectIfClosedByClient() async throws {
        let opens = Locked(0)
        let closes = Locked(0)
        let ws: WebSocket = fake(
            onOpen: { opens.access { $0 += 1 }},
            onClose: { _ in closes.access { $0 += 1 }}
        )
        try await withWebSocket(ws) { socket in
            await socket.connect()
            XCTAssertEqual(1, opens.access { $0 })
            XCTAssertEqual(0, closes.access { $0 })

            await socket.disconnect()
            XCTAssertEqual(1, opens.access { $0 })
            XCTAssertEqual(1, closes.access { $0 })

            try await Task.sleep(nanoseconds: NSEC_PER_MSEC * 50)
        }

        XCTAssertEqual(1, opens.access { $0 })
        XCTAssertEqual(1, closes.access { $0 })
    }

    func testReconnectsIfClosedRemotely() async throws {
        let opens = Locked(0)
        let closes = Locked(0)
        let ws: WebSocket = fake(
            onOpen: { opens.access { $0 += 1 }},
            onClose: { _ in closes.access { $0 += 1 }}
        )

        // Since we never answer the heartbeat, the socket connection will
        // close automatically after 0.01 seconds, and then the socket
        // should try to reconnect.
        try await withWebSocket(ws, timeout: 0.01, heartbeatInterval: 0.01) { socket in
            await socket.connect()
            XCTAssertEqual(1, opens.access { $0 })
            XCTAssertEqual(0, closes.access { $0 })

            await AssertTrueEventually(opens.access { $0 } > 1)

            XCTAssertGreaterThanOrEqual(1, closes.access { $0 })
        }
    }

    func testTriggersChannelErrorIfJoining() async throws {
        let didErrorWhileJoining = Locked(false)

        try await withWebSocket(
            fake(),
            timeout: 0.01,
            heartbeatInterval: 0.01
        ) { socket in
            await socket.connect()
            let channel = await socket.channel("abc", rejoinDelay: [0, 0.01])

            let task = Task {
                do {
                    try await channel.join(timeout: 10)
                    XCTFail("Should not have joined")
                } catch {
                    didErrorWhileJoining.access { $0 = true }
                }
            }

            await task.value
            XCTAssertTrue(didErrorWhileJoining.access { $0 })
        }
    }

    func testTriggersChannelErrorIfJoined() async throws {
        try await withWebSocket(fake()) { socket in
            await socket.connect()
            let channel = await socket.channel("abc", rejoinDelay: [0, 0.01])

            let isErrored = AsyncThrowingFuture<Void>()

            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    for await msg in self.outgoingMessages {
                        let message = try Message.decode(msg)

                        if message.event == .join {
                            try self.sendReply(for: message)
                            try await Task.sleep(nanoseconds: NSEC_PER_MSEC * 10)
                            self.receiveSubject.send(
                                .text(#"[1,2,"abc","phx_error",{}]"#)
                            )
                            break
                        }
                    }
                }

                group.addTask {
                    for await message in channel.messages {
                        if message.event == .error {
                            isErrored.resolve()
                            XCTAssertTrue(channel.isErrored || channel.isJoining)
                            break
                        }
                    }
                }

                await self.wait()
                try await channel.join()

                try await isErrored.value
                group.cancelAll()
            }
        }
    }

    // MARK: "onConnMessage"

    func testParsesRawMessageAndSendsToCorrectChannel() async throws {
        let didReceiveMessage = Locked(false)

        try await withWebSocket(fake()) { socket in
            await socket.connect()
            let channel1 = await socket.channel("abc")
            let channel2 = await socket.channel("def")

            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    for await msg in self.outgoingMessages {
                        let message = try Message.decode(msg)

                        if message.event == .join {
                            try self.sendReply(for: message)
                        }
                    }
                }

                group.addTask {
                    for await message in channel1.messages {
                        if message.event == .custom("test") {
                            didReceiveMessage.access { $0 = true }
                            break
                        }
                    }
                }

                group.addTask {
                    var count = 0
                    for await message in channel2.messages {
                        // Should only receive join reply
                        if count > 0 {
                            XCTFail("Should not have received message: \(message)")
                        } else {
                            count += 1
                        }
                    }
                }

                await self.wait()

                try await channel1.join()
                try await channel2.join()

                self.receiveSubject.send(
                    WebSocketMessage.text(#"[1,1,"abc","test",{}]"#)
                )

                try await group.next()

                await self.wait()
                group.cancelAll()

                XCTAssertTrue(didReceiveMessage.access { $0 })
            }
        }
    }
}

private extension PhoenixSocketTests {
    var push1: Push {
        Push(
            topic: "topic",
            event: "event",
            payload: ["one": 1] as JSON
        )
    }

    var encodedPush1: WebSocketMessage {
        let push = push1
        push.prepareToSend(ref: 1)
        return try! Push.encode(push)
    }

    func makePushes(_ count: Int) -> [Push] {
        (1 ... count).map { i in
            Push(
                topic: "test",
                event: .custom(String(i)),
                payload: ["index": i]
            )
        }
    }

    func heartbeat(ref: Int) -> WebSocketMessage {
        .text("""
        [null,\(ref),"phoenix","heartbeat",{}]
        """)
    }

    func heartbeatReply(ref: Int) -> WebSocketMessage {
        .text("""
        [null,\(ref),"phoenix","phx_reply",{"response":{},"status":"ok"}]
        """)
    }
}

private func future(
    timeout: TimeInterval
) -> AsyncThrowingFuture<Void> {
    .init(timeout: timeout)
}

private extension PhoenixSocketTests {
    func system(
        onOpen: @escaping WebSocketOnOpen = {},
        onClose: @escaping WebSocketOnClose = { _ in }
    ) async throws -> WebSocket {
        try await .system(url: url(), onOpen: onOpen, onClose: onClose)
    }

    func fake(
        onOpen: @escaping WebSocketOnOpen = {},
        onClose: @escaping WebSocketOnClose = { _ in },
        onSend: @escaping (WebSocketMessage) -> Void = { _ in },
        open: (@Sendable () async throws -> Void)? = nil,
        close: (@Sendable (WebSocketCloseCode, TimeInterval?) async throws -> Void)? = nil
    ) -> WebSocket {
        let _open = open ?? { @Sendable () async throws in
            onOpen()
        }
        let _close = close ??
            { @Sendable (code: WebSocketCloseCode, _: TimeInterval?) async throws in
                onClose(WebSocketClose(code, nil))
            }

        return WebSocket(
            id: .random(in: 1 ... 1_000_000_000),
            open: _open,
            close: _close,
            send: { message in
                self.sendSubject.send(message)
                onSend(message)
            },
            messagesPublisher: { self.receiveSubject.eraseToAnyPublisher() }
        )
    }

    var makeFakeWebSocket: MakeWebSocket {
        { [weak self] _, _, _, onOpen, onClose async throws in
            guard let self else { throw CancellationError() }
            return fake(onOpen: onOpen, onClose: onClose)
        }
    }

    func withWebSocket(
        _ ws: WebSocket,
        timeout: TimeInterval = 10,
        heartbeatInterval: TimeInterval = 30,
        onOpen: @escaping () -> Void = {},
        onClose: @escaping () -> Void = {},
        block: @escaping (PhoenixSocket) async throws -> Void
    ) async throws {
        let makeWS: MakeWebSocket = { _, _, _, _, _ in ws }

        let socket = PhoenixSocket(
            url: url,
            timeout: timeout,
            heartbeatInterval: heartbeatInterval,
            makeWebSocket: makeWS
        )

        let sub = socket
            .onConnectionStateChange
            .dropFirst() // Drop the initial .closed
            .sink { state in
                switch state {
                case .connecting: break
                case .open: onOpen()
                case .waitingToReconnect: break
                case .preparingToReconnect: break
                case .closing: break
                case .closed: onClose()
                }
            }

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await Task.sleep(nanoseconds: 2 * NSEC_PER_SEC)
                guard !Task.isCancelled else { return }
                throw CancellationError()
            }
            group.addTask { try await block(socket) }

            try await group.next()
            group.cancelAll()
        }

        await socket.disconnect(timeout: 0.000001)
        sub.cancel()
    }

    var outgoingMessages: AsyncStream<WebSocketMessage> {
        sendSubject.allAsyncValues
    }

    func sendReply(
        for message: Message,
        payload: JSON = [:]
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
                        "response": payload.dictionaryValue!,
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

private extension [Push] {
    mutating func remove(matching webSocketMessage: WebSocketMessage) -> Bool {
        guard let message = try? Message.decode(webSocketMessage),
              let index = firstIndex(where: { $0.ref == message.ref })
        else { return false }

        remove(at: index)
        return true
    }
}
