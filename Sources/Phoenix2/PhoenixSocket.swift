import Collections
// import AsyncAlgorithms
import Foundation
import os.log
import Synchronized
import WebSocket

typealias MakeWebSocket =
    (
        URL,
        WebSocketOptions,
        @escaping WebSocketOnOpen,
        @escaping WebSocketOnClose
    ) async throws -> WebSocket

actor PhoenixSocket {
    var webSocket: WebSocket? {
        switch connectionState {
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

    nonisolated let pushEncoder: PushEncoder
    nonisolated let messageDecoder: MessageDecoder

    private let makeWebSocket: MakeWebSocket

    private(set) var connectionState: ConnectionState = .closed {
        didSet { onConnectionStateChange(connectionState) }
    }

    private let onConnectionStateChange: (ConnectionState) -> Void

    private var shouldReconnect: Bool = true
    private var reconnectAttempts: Int = 0

    private(set) var ref: Ref = .init(0)

    private(set) var channels: [Topic: PhoenixChannel] = [:]

    private nonisolated let pushes = PushBuffer(isActive: false)

    private var heartbeatTask: Task<Void, Error>?

    init(
        url: URL,
        connectionOptions: [String: Any] = [:],
        timeout: TimeInterval = 10,
        heartbeatInterval: TimeInterval = 30,
        pushEncoder: @escaping PushEncoder = Push.encode,
        messageDecoder: @escaping MessageDecoder = Message.decode,
        makeWebSocket: @escaping MakeWebSocket,
        onConnectionStateChange: @escaping (ConnectionState) -> Void = { _ in }
    ) {
        self.url = url.webSocketURLV2
        connectOptions = connectionOptions
        self.timeout = UInt64(timeout) * NSEC_PER_SEC
        self.heartbeatInterval = UInt64(heartbeatInterval) * NSEC_PER_SEC
        self.pushEncoder = pushEncoder
        self.messageDecoder = messageDecoder
        self.makeWebSocket = makeWebSocket
        self.onConnectionStateChange = onConnectionStateChange
    }

    func connect() async throws {
        guard case .closed = connectionState else { return }
        reconnectAttempts = 0
        shouldReconnect = true
        try await reconnect(attempts: reconnectAttempts)
    }

    /// Connects to the socket. If `attempt` is 0, this is the first
    /// connection attempt. Otherwise, a previous connection failed
    /// and this one will happen after a delay.
    private func reconnect(attempts: Int) async throws {
        guard case .closed = connectionState, shouldReconnect else { return }

        connectionState = .waitingToReconnect

        if let timeout = Self.retryTimeout(attempts: attempts) {
            try await Task.sleep(nanoseconds: NSEC_PER_SEC * UInt64(timeout))
        }

        guard case .waitingToReconnect = connectionState, shouldReconnect else { return }

        os_log(
            "phoenix.reconnect: oldstate=%{public}@",
            log: .phoenix,
            type: .debug,
            connectionState.description
        )

        let ws = try await makeWebSocket(url, .init(), {}, { _ in })
        connectionState = .connecting(ws)

        do {
            try await ws.open(TimeInterval(timeout / NSEC_PER_SEC))

            connectionState = .open(ws)
            reconnectAttempts = 0
            pushes.isActive = true
            flush()
            scheduleHeartbeat()

        } catch {
            connectionState = .closed
            reconnectAttempts += 1
            try await reconnect(attempts: reconnectAttempts)
        }
    }

    func disconnect(timeout: TimeInterval? = nil) async throws {
        os_log(
            "phoenix.disconnect: oldstate=%{public}@",
            log: .phoenix,
            type: .debug,
            connectionState.description
        )

        shouldReconnect = false
        pushes.isActive = false
        cancelHeartbeat()

        switch connectionState {
        case .waitingToReconnect, .closed, .closing:
            return

        case let .connecting(ws):
            // cancelHeartbeatTimer()
            connectionState = .closing(ws)
            try await ws.close(.normalClosure, timeout)
            connectionState = .closed

        case let .open(ws):
            // cancelHeartbeatTimer()
            connectionState = .closing(ws)
            // try await flushPendingMessagesAndWait()
            try await ws.close(.normalClosure, timeout)
            connectionState = .closed
        }
    }
}

extension PhoenixSocket {
    func channel(_ topic: Topic, joinPayload: Payload = [:]) -> PhoenixChannel {
        if let channel = channels[topic] {
            return channel
        } else {
            let channel = PhoenixChannel(
                topic: topic,
                joinPayload: joinPayload,
                socket: self
            )
            channels[topic] = channel
            return channel
        }
    }

    func remove(_ channel: PhoenixChannel) {
        remove(channel.topic)
    }

    func remove(_ topic: Topic) {
        channels.removeValue(forKey: topic)
    }
}

extension PhoenixSocket {
    func push(_ push: Push, waitForReply: Bool = true) async throws {
        os_log(
            "phoenix.push: %@",
            log: .phoenix,
            type: .debug,
            push.description
        )

        if waitForReply {
            let message = try await pushes.appendAndWait(push)
            Swift.print("$$$ RECEIVED MESSAGE: \(message)")
        } else {
            try await pushes.append(push)
        }
    }

    func makeRef() async -> Ref {
        let newRef = ref.next
        ref = newRef
        return newRef
    }

    private func flush() {
        Task { [weak self] in
            guard let self = self, !Task.isCancelled,
                  let ws = await self.webSocket else { return }

            do {
                let encoder = self.pushEncoder

                for try await push in self.pushes {
                    os_log(
                        "phoenix.send: %@",
                        log: .phoenix,
                        type: .debug,
                        push.description
                    )

                    try await ws.send(encoder(push))
                    self.pushes.didSend(push)

                    if Task.isCancelled { break }
                }
            } catch {}
        }
    }
}

extension PhoenixSocket {
    private func scheduleHeartbeat() {
        cancelHeartbeat()

        let interval = heartbeatInterval
        heartbeatTask = Task.detached { [weak self] in
            try await Task.sleep(nanoseconds: interval)
            try await self?.sendHeartbeat()
        }
    }

    private func cancelHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
    }

    private func sendHeartbeat() async throws {
        guard connectionState.isOpen else { return }

//        await withTaskGroup(of: Void.self) { group in
//            let heartbeatRef = await self.makeRef()
//
//            group.addTaskUnlessCancelled {
//                await withCheckedContinuation { [weak self] (continuation: CheckedContinuation<Void, Error>) -> Void in
//                    guard let self = self else { return continuation.resume() }
//                    self.lock.locked { self.heartbeatContinuation = (heartbeatRef, continuation) }
//                }
//            }
//
//            group.addTaskUnlessCancelled { [weak self] in
//                guard let self = self else { return }
//                do {
//
//
//                    withCheckedContinuation { continuation in
//
//                    }
//
//                    try await self.push(
//                        .init(
//                            joinRef: nil,
//                            ref: heartbeatRef,
//                            topic: "phoenix",
//                            event: .heartbeat
//                        )
//                    )
//                } catch {
//
//                }
//            }
//        }

        scheduleHeartbeat()
    }
}

extension PhoenixSocket {
    enum ConnectionState: CustomStringConvertible {
        case closed
        case waitingToReconnect
        case connecting(WebSocket)
        case open(WebSocket)
        case closing(WebSocket)

        var isClosed: Bool {
            guard case .closed = self else { return false }
            return true
        }

        var isWaitingToReconnect: Bool {
            guard case .waitingToReconnect = self else { return false }
            return true
        }

        var isConnecting: Bool {
            guard case .connecting = self else { return false }
            return true
        }

        var isOpen: Bool {
            guard case .open = self else { return false }
            return true
        }

        var isClosing: Bool {
            guard case .closing = self else { return false }
            return true
        }

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
