import Foundation
import WebSocket
import os.log

typealias MakeWebSocket =
    (
        URL,
        WebSocketOptions,
        @escaping WebSocketOnOpen,
        @escaping WebSocketOnClose
    ) async throws -> WebSocket

actor PhoenixSocket {
    var webSocket: WebSocket? {
        switch state {
        case let .connecting(ws), let .open(ws), let .closing(ws):
            return ws

        case .waitingToReconnect, .closed:
            return nil
        }
    }

    nonisolated let url: URL
    nonisolated let connectOptions: [String: Any]
    nonisolated let timeout: UInt64
    nonisolated let heartbeatInterval: UInt64

    private let makeWebSocket: MakeWebSocket

    private var state: State = .closed { didSet { onStateChange(state) } }
    private let onStateChange: (State) -> Void

    private var shouldReconnect: Bool = true
    private var reconnectAttempts: Int = 0

    init(
        url: URL,
        connectionOptions: [String: Any] = [:],
        timeout: TimeInterval = 10,
        heartbeatInterval: TimeInterval = 30,
        makeWebSocket: @escaping MakeWebSocket,
        onStateChange: @escaping (State) -> Void = { _ in }
    ) {
        self.url = url.webSocketURLV2
        self.connectOptions = connectionOptions
        self.timeout = UInt64(timeout) * NSEC_PER_SEC
        self.heartbeatInterval = UInt64(heartbeatInterval) * NSEC_PER_SEC
        self.makeWebSocket = makeWebSocket
        self.onStateChange = onStateChange
    }

    func connect() async throws {
        guard case .closed = state else { return }
        reconnectAttempts = 0
        shouldReconnect = true
        try await reconnect(attempts: reconnectAttempts)
    }

    /// Connects to the socket. If `attempt` is 0, this is the first
    /// connection attempt. Otherwise, a previous connection failed
    /// and this one will happen after a delay.
    private func reconnect(attempts: Int) async throws {
        guard case .closed = state, shouldReconnect else { return }

        state = .waitingToReconnect

        if let timeout = Self.retryTimeout(attempts: attempts) {
            try await Task.sleep(nanoseconds: NSEC_PER_SEC * UInt64(timeout))
        }

        guard case .waitingToReconnect = state, shouldReconnect else { return }

        os_log(
            "socket.reconnect: oldstate=%{public}@",
            log: .phoenix,
            type: .debug,
            state.description
        )

        let ws = try await makeWebSocket(url, .init(), {}, {_ in})
        state = .connecting(ws)

        do {
            try await ws.open(TimeInterval(timeout / NSEC_PER_SEC))
            
            state = .open(ws)
            reconnectAttempts = 0
            // flush()
            // startHeartbeatTimer()
        } catch {
            state = .closed
            reconnectAttempts += 1
            try await reconnect(attempts: reconnectAttempts)
        }
    }

    func disconnect(timeout: TimeInterval? = nil) async throws {
        os_log(
            "socket.disconnect: oldstate=%{public}@",
            log: .phoenix,
            type: .debug,
            state.description
        )

        shouldReconnect = false

        switch state {
        case .waitingToReconnect, .closed, .closing:
            return

        case let .connecting(ws):
            // cancelHeartbeatTimer()
            state = .closing(ws)
            try await ws.close(.normalClosure, timeout)
            state = .closed

        case let .open(ws):
            // cancelHeartbeatTimer()
            state = .closing(ws)
            // try await flushPendingMessagesAndWait()
            try await ws.close(.normalClosure, timeout)
            state = .closed
        }
    }
}

extension PhoenixSocket {
    enum State: CustomStringConvertible {
        case closed
        case waitingToReconnect
        case connecting(WebSocket)
        case open(WebSocket)
        case closing(WebSocket)

        var description: String {
            switch self {
            case .closed: return "closed"
            case .waitingToReconnect: return "waitingToReconnect"
            case .connecting: return "connecting"
            case .open: return "open"
            case .closing: return "closing"
            }
        }
    }
}

private extension PhoenixSocket {
    static func retryTimeout(attempts: Int) -> TimeInterval? {
        guard attempts > 0 else { return nil }
        guard attempts < 9 else { return 5 }
        return [0.01, 0.05, 0.1, 0.15, 0.2, 0.25, 0.5, 1, 2][attempts]
    }
}

private extension URL {
    var webSocketURLV2: URL {
        var copy = self
        // TODO: Do this in consumers, not here.
        if copy.lastPathComponent != "websocket" {
            copy.appendPathComponent("websocket")
        }
        return copy.appendingQueryItems(["vsn": "2.0.0"])
    }
}
