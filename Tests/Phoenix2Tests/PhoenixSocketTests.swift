// import AsyncTestExtensions
// import Combine
// @testable import Phoenix2
// import Synchronized
// import WebSocket
// import XCTest
//
//// NOTE: Names in quotation marks below correspond to groups of tests
//// delimited by `describe("some name", {})` blocks in Phoenix JS'
//// test suite, which can be found here:
//// https://github.com/phoenixframework/phoenix/blob/v1.6.10/assets/test/socket_test.js
//
// final class PhoenixSocketTests: XCTestCase {
//    private let url = URL(string: "ws://0.0.0.0:4003/socket")!
//
//    // MARK: "constructor" and "endpointURL"
//
//    func testSocketInitWithDefaults() async throws {
//        let socket = PhoenixSocket(
//            url: url,
//            makeWebSocket: makeFakeWebSocket
//        )
//
//        let url = socket.url
//        XCTAssertEqual(url.path, "/socket/websocket")
//        XCTAssertEqual(url.query, "vsn=2.0.0")
//
//        XCTAssertEqual(10 * NSEC_PER_SEC, socket.timeout)
//        XCTAssertEqual(30 * NSEC_PER_SEC, socket.heartbeatInterval)
//    }
//
//    func testSocketInitWithCustomValues() async throws {
//        let socket = PhoenixSocket(
//            url: url,
//            timeout: 12,
//            heartbeatInterval: 29,
//            makeWebSocket: makeFakeWebSocket
//        )
//
//        let url = socket.url
//        XCTAssertEqual(url.path, "/socket/websocket")
//        XCTAssertEqual(url.query, "vsn=2.0.0")
//
//        XCTAssertEqual(12 * NSEC_PER_SEC, socket.timeout)
//        XCTAssertEqual(29 * NSEC_PER_SEC, socket.heartbeatInterval)
//    }
//
//    // MARK: "connect with WebSocket"
//
//    func testConnectsToCorrectURL() async throws {
//        var createdWebSocket = false
//        let expected = URL(string: "ws://0.0.0.0:4003/socket/websocket?vsn=2.0.0")!
//
//        let makeWS: MakeWebSocket = { url, _, _, _ in
//            createdWebSocket = true
//            XCTAssertEqual(expected, url)
//            return self.fake()
//        }
//
//        let socket = PhoenixSocket(url: url, makeWebSocket: makeWS)
//        try await socket.connect()
//
//        XCTAssertTrue(createdWebSocket)
//    }
//
//    func testOpenStateCallbackIsCalled() async throws {
//        var opens = 0
//        let onOpen: () -> Void = { opens += 1 }
//
//        try await withWebSocket(fake(), onOpen: onOpen) { socket in
//            try await socket.connect()
//        }
//
//        XCTAssertEqual(1, opens)
//    }
//
//    func testCallingConnectWhileConnectedIsNoop() async throws {
//        let socket = PhoenixSocket(url: url, makeWebSocket: makeFakeWebSocket)
//
//        try await socket.connect()
//        let id1 = await socket.webSocket?.id
//        XCTAssertNotNil(id1)
//
//        try await socket.connect()
//        let id2 = await socket.webSocket?.id
//        XCTAssertEqual(id1, id2)
//    }
//
//    // MARK: "disconnect"
//
//    func testDisconnectDestroysWebSocket() async throws {
//        let socket = PhoenixSocket(url: url, makeWebSocket: makeFakeWebSocket)
//
//        try await socket.connect()
//        await AssertNotNil(await socket.webSocket?.id)
//
//        try await socket.disconnect()
//        await AssertNil(await socket.webSocket?.id)
//    }
//
//    func testCloseStateCallbackIsCalled() async throws {
//        let closes = Locked(0)
//        let onPhoenixClose: () -> Void = { closes.access { $0 += 1 } }
//        let onClose: WebSocketOnClose = { (close: WebSocketClose) -> Void in
//            closes.access { $0 += 1 }
//            XCTAssertEqual(.normalClosure, close.code)
//            XCTAssertTrue(close.isNormal)
//            XCTAssertNil(close.reason)
//        }
//
//        try await withWebSocket(
//            fake(onOpen: {}, onClose: onClose),
//            onClose: onPhoenixClose
//        ) { socket in
//            try await socket.connect()
//            try await socket.disconnect()
//        }
//
//        XCTAssertEqual(2, closes.access { $0 })
//    }
//
//    func testDisconnectIsNoopWhenNotConnected() async throws {
//        let closes = Locked(0)
//        let onPhoenixClose: () -> Void = { closes.access { $0 += 1 } }
//        let onClose: WebSocketOnClose = { _ in closes.access { $0 += 1 } }
//
//        try await withWebSocket(
//            fake(onOpen: {}, onClose: onClose),
//            onClose: onPhoenixClose
//        ) { socket in
//            try await socket.disconnect()
//            try await socket.disconnect()
//            try await socket.disconnect()
//        }
//
//        XCTAssertEqual(0, closes.access { $0 })
//    }
//
//    // MARK: "connectionState"
//
//    func testConnectionStateIsClosedInitially() async throws {
//        try await withWebSocket(fake()) { socket in
//            await AssertTrue(await socket.connectionState.isClosed)
//        }
//    }
//
//    func testConnectionStateIsConnectingWhenConnecting() async throws {
//        var didChangeToConnecting = false
//        let socket = PhoenixSocket(url: url, makeWebSocket: makeFakeWebSocket) { state in
//            guard state.isConnecting else { return }
//            guard !didChangeToConnecting
//            else { return XCTFail("Should have only changed to connecting once") }
//            didChangeToConnecting = true
//        }
//        try await socket.connect()
//        XCTAssertTrue(didChangeToConnecting)
//    }
//
//    func testConnectionStateIsOpenAfterConnecting() async throws {
//        try await withWebSocket(fake()) { socket in
//            try await socket.connect()
//            await AssertTrue(await socket.connectionState.isOpen)
//        }
//    }
//
//    func testConnectionStateIsClosingWhenDisconnecting() async throws {
//        var didChangeToClosing = false
//        let socket = PhoenixSocket(url: url, makeWebSocket: makeFakeWebSocket) { state in
//            guard state.isClosing else { return }
//            guard !didChangeToClosing
//            else { return XCTFail("Should have only changed to closing once") }
//            didChangeToClosing = true
//        }
//        try await socket.connect()
//        try await socket.disconnect()
//        XCTAssertTrue(didChangeToClosing)
//    }
//
//    func testConnectionStateIsClosedAfterDisconnecting() async throws {
//        try await withWebSocket(fake()) { socket in
//            try await socket.connect()
//            await AssertTrue(await socket.connectionState.isOpen)
//
//            try await socket.disconnect()
//            await AssertTrue(await socket.connectionState.isClosed)
//        }
//    }
//
//    // MARK: "channel"
//
//    func testCreateChannelWithTopicAndPayload() async throws {
//        try await withWebSocket(fake()) { socket in
//            let channel = await socket.channel("topic", joinPayload: ["one": "two"])
//            XCTAssertEqual("topic", channel.topic)
//            XCTAssertEqual(["one": "two"], channel.joinPayload)
//        }
//    }
//
//    func testCreatingChannelsAddsItToChannelsDictionary() async throws {
//        try await withWebSocket(fake()) { socket in
//            _ = await socket.channel("topic", joinPayload: ["one": "two"])
//
//            let channels = await socket.channels
//            XCTAssertEqual(1, channels.count)
//            let channel = try XCTUnwrap(channels["topic"])
//
//            XCTAssertEqual("topic", channel.topic)
//            XCTAssertEqual(["one": "two"], channel.joinPayload)
//        }
//    }
//
//    // TODO: Test calling `channel()` twice with the same topic only creates
//    // one channel. _This is different from Phoenix JS's native behavior_
//
//    // MARK: "remove"
//
//    func testRemoveRemovesChannelFromChannelsDictionary() async throws {
//        try await withWebSocket(fake()) { socket in
//            let channel1 = await socket.channel("topic-1")
//            let channel2 = await socket.channel("topic-2")
//            await AssertEqual(2, await socket.channels.count)
//
//            await socket.remove(channel1)
//
//            await AssertEqual(1, await socket.channels.count)
//
//            let channel = await socket.channels.first?.value
//            XCTAssertEqual(channel2.topic, channel?.topic)
//        }
//    }
//
//    // MARK: "push"
//
//    func testPushSendsDataToWebSocketWhenConnected() async throws {
//        var sent = [WebSocketMessage]()
//
//        let ws: WebSocket = fake(onSend: { sent.append($0) })
//        try await withWebSocket(ws) { socket in
//            try await socket.connect()
//            try await socket.push(self.push1) as Void
//            await AssertEqualEventually(self.encodedPush1, sent.first)
//        }
//    }
//
//    func testBuffersDataWhenWebSocketIsNotConnected() async throws {
//        let canSend = Locked(false)
//        let didSend = Locked(false)
//
//        let ws: WebSocket = fake(
//            onSend: { message in
//                if canSend.access({ $0 }) {
//                    XCTAssertEqual(self.encodedPush1, message)
//                    didSend.access { $0 = true }
//                } else {
//                    XCTFail("Should not have received a message")
//                }
//            }
//        )
//
//        try await withWebSocket(ws) { socket in
//            Task.detached { try await socket.push(self.push1) as Void }
//            let sleep = Task {
//                try await Task.sleep(nanoseconds: NSEC_PER_MSEC * 50)
//                canSend.access { $0 = true }
//            }
//            try await sleep.value
//
//            try await socket.connect()
//            await AssertEqualEventually(true, didSend.access { $0 })
//        }
//    }
//
//    // MARK: "makeRef"
//
//    func testRefNextReturnsNextRef() async throws {
//        try await withWebSocket(fake()) { socket in
//            await AssertEqual(0, socket.ref)
//
//            let one = await socket.makeRef()
//            XCTAssertEqual(1, one)
//            await AssertEqual(1, socket.ref)
//
//            let two = await socket.makeRef()
//            XCTAssertEqual(2, two)
//            await AssertEqual(2, socket.ref)
//
//            let three = await socket.makeRef()
//            XCTAssertEqual(3, three)
//            await AssertEqual(3, socket.ref)
//        }
//    }
//
//    func testRefRestartsAtZeroAfterOverflow() throws {
//        let ref: Ref = 9_007_199_254_740_991
//        XCTAssertEqual(0, ref.next)
//    }
//
//    // MARK: "sendHeartbeat"
//
//    func testClosesSocketWhenHeartbeatIsNotAcknowledged() async throws {
//        let didClose = Locked(false)
//
//        let ws: WebSocket = fake(
//            onClose: { _ in didClose.access { $0 = true } },
//            onSend: { _ in }
//        )
//
//        try await withWebSocket(ws, timeout: 0.05, heartbeatInterval: 0.05) { socket in
//            try await socket.connect()
//            await AssertTrueEventually((didClose.access { $0 }))
//        }
//    }
//
//    func testPushesHeartbeatWhenConnected() async throws {
//        let didSendHeartbeat = Locked(false)
//
//        let ws: WebSocket = fake(
//            onSend: { message in
//                switch message {
//                case .data:
//                    XCTFail()
//
//                case let .text(text):
//                    let expected = """
//                    [null,1,"phoenix","heartbeat",{}]
//                    """
//                    XCTAssertEqual(expected, text)
//                }
//                didSendHeartbeat.access { $0 = true }
//            }
//        )
//
//        try await withWebSocket(ws, heartbeatInterval: 0.1) { socket in
//            try await socket.connect()
//            await AssertTrueEventually((didSendHeartbeat.access { $0 }))
//        }
//    }
//
//    func testDoesNotPushHeartbeatWhenNotConnected() async throws {
//        let ws: WebSocket = fake(onSend: { _ in XCTFail() })
//
//        try await withWebSocket(ws, heartbeatInterval: 0.05) { socket in
//            try await Task.sleep(nanoseconds: NSEC_PER_MSEC * 150)
//        }
//    }
//
//    // MARK: "flushSendBuffer"
//
//    func testFlushesAllMessagesInBufferWhenConnected() async throws {
//        let pushes = Locked(makePushes(5))
//
//        let ws: WebSocket = fake(onSend: { msg in
//            _ = pushes.access { $0.remove(matching: msg) }
//        })
//
//        try await withWebSocket(ws) { socket in
//            Task {
//                // Wait until all of the pushes have been added
//                try await Task.sleep(nanoseconds: NSEC_PER_MSEC * 50)
//                try await socket.connect()
//            }
//
//            try await withThrowingTaskGroup(of: Void.self) { group in
//                pushes
//                    .access { $0 }
//                    .forEach { push in
//                        group.addTask { try await socket.push(push) }
//                    }
//                try await group.waitForAll()
//            }
//
//            XCTAssertTrue(pushes.access { $0.isEmpty })
//        }
//    }
//
//    // MARK: "onConnOpen"
//
//    func testSendBufferIsFlushedOnConnect() async throws {
//        let pushes = Locked(makePushes(2))
//
//        let ws: WebSocket = fake(onSend: { msg in
//            XCTAssertTrue(pushes.access { $0.remove(matching: msg) })
//        })
//
//        try await withWebSocket(ws) { socket in
//            Task {
//                // Wait until all of the pushes have been added
//                try await Task.sleep(nanoseconds: NSEC_PER_MSEC * 50)
//                try await socket.connect()
//            }
//
//            try await withThrowingTaskGroup(of: Void.self) { group in
//                pushes
//                    .access { $0 }
//                    .forEach { push in
//                        group.addTask { try await socket.push(push) }
//                    }
//                try await group.waitForAll()
//            }
//
//            XCTAssertTrue(pushes.access { $0.isEmpty })
//        }
//    }
//
//    func testReconnectTimerIsResetOnConnect() async throws {
//        struct NoInternet: Error {}
//
//        let attempts = Locked(0)
//
//        let ws: WebSocket = fake(
//            open: { _ in
//                defer { attempts.access { $0 += 1 } }
//                if attempts.access({ $0 < 3 }) {
//                    throw  NoInternet()
//                }
//            }
//        )
//
//        try await withWebSocket(ws) { socket in
//            try await socket.connect()
//            await AssertEqual(0, await socket.reconnectAttempts)
//        }
//    }
//
//    func testCallsOnOpenCallbackOnConnect() async throws {
//        let didCall = Locked(false)
//        try await withWebSocket(
//            self.fake(),
//            onOpen: { didCall.access { $0 = true } }
//        ) { socket in
//            try await socket.connect()
//            XCTAssertTrue(didCall.access { $0 })
//        }
//    }
//
//    // MARK: "onConnClose"
//
//    // This test differs from the original, which is called
//    // "does not schedule reconnectTimer if normal close".
//    // We always try to reconnect unless the connection was
//    // closed by the client.
//    func testDoesNotReconnectIfClosedByClient() async throws {
//        let opens = Locked(0)
//        let closes = Locked(0)
//        let ws: WebSocket = fake(
//            onOpen: { opens.access { $0 += 1 }},
//            onClose: { _ in closes.access { $0 += 1 }}
//        )
//        try await withWebSocket(ws) { socket in
//            try await socket.connect()
//            XCTAssertEqual(1, opens.access { $0 })
//            XCTAssertEqual(0, closes.access { $0 })
//
//            try await socket.disconnect()
//            XCTAssertEqual(1, opens.access { $0 })
//            XCTAssertEqual(1, closes.access { $0 })
//
//            try await Task.sleep(nanoseconds: NSEC_PER_MSEC * 50)
//        }
//
//        XCTAssertEqual(1, opens.access { $0 })
//        XCTAssertEqual(1, closes.access { $0 })
//    }
//
//    func testReconnectsIfClosedRemotely() async throws {
//        let opens = Locked(0)
//        let closes = Locked(0)
//        let ws: WebSocket = fake(
//            onOpen: { opens.access { $0 += 1 }},
//            onClose: { _ in closes.access { $0 += 1 }}
//        )
//        try await withWebSocket(ws, timeout: 0.01, heartbeatInterval: 0.01) { socket in
//            try await socket.connect()
//            XCTAssertEqual(1, opens.access { $0 })
//            XCTAssertEqual(0, closes.access { $0 })
//
//            await AssertTrueEventually(opens.access({ $0 }) > 1)
//
//            XCTAssertLessThan(1, opens.access { $0 })
//        }
//
//    }
// }
//
// private extension PhoenixSocketTests {
//    var push1: Push {
//        Push(
//            joinRef: .init(1),
//            ref: .init(2),
//            topic: "topic",
//            event: "event",
//            payload: ["one": 1] as Payload
//        )
//    }
//
//    var encodedPush1: WebSocketMessage {
//        try! Push.encode(push1)
//    }
//
//    func makePushes(_ count: Int) -> [Push] {
//        (1...count).map { i in
//            Push(
//                joinRef: 1,
//                ref: Ref(UInt64(i)),
//                topic: "test",
//                event: .custom(String(i)),
//                payload: ["index": i]
//            )
//        }
//    }
// }
//
// private extension PhoenixSocketTests {
//    func system(
//        onOpen: @escaping WebSocketOnOpen = {},
//        onClose: @escaping WebSocketOnClose = { _ in }
//    ) async throws -> WebSocket {
//        try await .system(url: url, onOpen: onOpen, onClose: onClose)
//    }
//
//    func fake(
//        onOpen: @escaping WebSocketOnOpen = {},
//        onClose: @escaping WebSocketOnClose = { _ in },
//        onSend: @escaping (WebSocketMessage) -> Void = { _ in },
//        open: (@Sendable (TimeInterval?) async throws -> Void)? = nil,
//        close: (@Sendable (WebSocketCloseCode, TimeInterval?) async throws -> Void)? = nil
//    ) -> WebSocket {
//        let _open = open ?? { _ in onOpen() }
//        let _close = close ?? { code, _ in onClose(.init(code, nil)) }
//        return WebSocket(
//            id: .random(in: 1 ... 1_000_000_000),
//            onOpen: onOpen,
//            onClose: onClose,
//            open: _open,
//            close: _close,
//            send: { onSend($0) }
//        )
//    }
//
//    var makeFakeWebSocket: MakeWebSocket {
//        { [weak self] _, _, onOpen, onClose async throws in
//            guard let self = self else { throw CancellationError() }
//            return self.fake(onOpen: onOpen, onClose: onClose)
//        }
//    }
//
//    func withWebSocket(
//        _ ws: WebSocket,
//        timeout: TimeInterval = 10,
//        heartbeatInterval: TimeInterval = 30,
//        onOpen: @escaping () -> Void = {},
//        onClose: @escaping () -> Void = {},
//        block: @escaping (PhoenixSocket) async throws -> Void
//    ) async throws {
//        let makeWS: MakeWebSocket = { _, _, _, _ in ws }
//
//        let socket = PhoenixSocket(
//            url: url,
//            timeout: timeout,
//            heartbeatInterval: heartbeatInterval,
//            makeWebSocket: makeWS
//        ) { state in
//            switch state {
//            case .connecting: break
//            case .open: onOpen()
//            case .waitingToReconnect: break
//            case .closing: break
//            case .closed: onClose()
//            }
//        }
//
//        try await withThrowingTaskGroup(of: Void.self) { group in
//            group.addTask {
//                try await Task.sleep(nanoseconds: 2 * NSEC_PER_SEC)
//                guard !Task.isCancelled else { return }
//                throw CancellationError()
//            }
//            group.addTask { try await block(socket) }
//
//            try await group.next()
//            group.cancelAll()
//        }
//
//        try await socket.disconnectImmediately()
//    }
// }
//
// private extension Array where Element == Push {
//    mutating func remove(matching webSocketMessage: WebSocketMessage) -> Bool {
//        guard let message = try? Message.decode(webSocketMessage),
//              let index = firstIndex(where: { $0.ref == message.ref })
//        else { return false }
//
//        remove(at: index)
//        return true
//    }
// }
