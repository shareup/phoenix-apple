import XCTest
@testable import Phoenix2
import Combine
import WebSocket

// NOTE: Names in quotation marks below correspond to groups of tests
// delimited by `describe("some name", {})` blocks in Phoenix JS'
// test suite, which can be found here:
// https://github.com/phoenixframework/phoenix/blob/v1.6.7/assets/test/socket_test.js

final class PhoenixSocketTests: XCTestCase {
    private let url = URL(string: "ws://0.0.0.0:4003/socket")!

    // MARK: "constructor" and "endpointURL"

    func testSocketInitWithDefaults() async throws {
        let socket = PhoenixSocket(
            url: url,
            makeWebSocket: makeFakeWebSocket
        )

        let url = socket.url
        XCTAssertEqual(url.path, "/socket/websocket")
        XCTAssertEqual(url.query, "vsn=2.0.0")

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
        XCTAssertEqual(url.path, "/socket/websocket")
        XCTAssertEqual(url.query, "vsn=2.0.0")

        XCTAssertEqual(12 * NSEC_PER_SEC, socket.timeout)
        XCTAssertEqual(29 * NSEC_PER_SEC, socket.heartbeatInterval)
    }

    // MARK: "connect with WebSocket"

    func testConnectsToCorrectURL() async throws {
        var createdWebSocket = false
        let expected = URL(string: "ws://0.0.0.0:4003/socket/websocket?vsn=2.0.0")!

        let makeWS: MakeWebSocket = { url, _, _, _ in
            createdWebSocket = true
            XCTAssertEqual(expected, url)
            return self.fake()
        }

        let socket = PhoenixSocket(url: url, makeWebSocket: makeWS)
        try await socket.connect()

        XCTAssertTrue(createdWebSocket)
    }

    func testOpenStateCallbackIsCalled() async throws {
        var opens = 0
        let onOpen: () -> Void = { opens += 1 }

        try await withWebSocket(self.fake(), onOpen: onOpen) { socket in
            try await socket.connect()
        }

        XCTAssertEqual(1, opens)
    }

    func testCallingConnectWhileConnectedIsNoop() async throws {
        let socket = PhoenixSocket(url: url, makeWebSocket: makeFakeWebSocket)

        try await socket.connect()
        let id1 = await socket.webSocket?.id
        XCTAssertNotNil(id1)

        try await socket.connect()
        let id2 = await socket.webSocket?.id
        XCTAssertEqual(id1, id2)
    }

    // MARK: "disconnect"

    func testDisconnectDestroysWebSocket() async throws {
        let socket = PhoenixSocket(url: url, makeWebSocket: makeFakeWebSocket)

        try await socket.connect()
        let id1 = await socket.webSocket?.id
        XCTAssertNotNil(id1)

        try await socket.disconnect()
        let id2 = await socket.webSocket?.id
        XCTAssertNil(id2)
    }

    func testCloseStateCallbackIsCalled() async throws {
        var closes = 0
        let onPhoenixClose: () -> Void = { closes += 1 }
        let onClose: WebSocketOnClose = { result in
            closes += 1
            switch result {
            case let .success((code, reason)):
                XCTAssertEqual(.normalClosure, code)
                XCTAssertNil(reason)

            case let .failure(error):
                XCTFail("Should not have received error: \(error)")
            }
        }

        try await withWebSocket(
            self.fake({}, onClose),
            onClose: onPhoenixClose
        ) { socket in
            try await socket.connect()
            try await socket.disconnect()
        }

        XCTAssertEqual(2, closes)
    }

    func testDisconnectIsNoopWhenNotConnected() async throws {
        var closes = 0
        let onPhoenixClose: () -> Void = { closes += 1 }
        let onClose: WebSocketOnClose = { _ in closes += 1 }

        try await withWebSocket(self.fake({}, onClose), onClose: onPhoenixClose) { socket in
            try await socket.disconnect()
            try await socket.disconnect()
            try await socket.disconnect()
        }

        XCTAssertEqual(0, closes)
    }

    // MARK: "connectionState"


}

private extension PhoenixSocketTests {
    func system(
        _ onOpen: @escaping WebSocketOnOpen = {},
        _ onClose: @escaping WebSocketOnClose = { _ in }
    ) async throws -> WebSocket {
        try await .system(url: url, onOpen: onOpen, onClose: onClose)
    }

    func fake(
        _ onOpen: @escaping WebSocketOnOpen = {},
        _ onClose: @escaping WebSocketOnClose = { _ in }
    ) -> WebSocket {
        WebSocket(
            id: .random(in: 1...1_000_000),
            onOpen: onOpen,
            onClose: onClose,
            open: { _ in onOpen() },
            close: { code, _ in onClose(.success((code, nil))) }
        )
    }

    var makeFakeWebSocket: MakeWebSocket {
        { [weak self] (_, _, onOpen, onClose) async throws in
            guard let self = self else { throw CancellationError() }
            return self.fake(onOpen, onClose)
        }
    }

    func withWebSocket(
        _ ws: WebSocket,
        onOpen: @escaping () -> Void = {},
        onClose: @escaping () -> Void = {},
        block: (PhoenixSocket) async throws -> Void
    ) async throws {
        let makeWS: MakeWebSocket = { _, _, _, _ in
            return ws
        }

        let socket = PhoenixSocket(url: url, makeWebSocket: makeWS) { state in
            switch state {
            case .connecting: break
            case .open: onOpen()
            case .waitingToReconnect: break
            case .closing: break
            case .closed: onClose()
            }
        }

        try await block(socket)
    }
}
