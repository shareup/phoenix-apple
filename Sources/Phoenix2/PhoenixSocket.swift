import Collections
import DispatchTimer
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

        case .waitingToReconnect, .preparingToReconnect, .closed:
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

    private(set) var shouldReconnect: Bool = true
    private(set) var reconnectAttempts: Int = 0

    nonisolated var ref: Ref { _ref.access { $0 } }
    private let _ref = Locked(Ref(0))

    private(set) var channels: [Topic: PhoenixChannel] = [:]

    private nonisolated let pushes = PushBuffer()

    private var flushTask: Task<Void, Error>?
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
        self.timeout = timeout.nanoseconds
        self.heartbeatInterval = heartbeatInterval.nanoseconds
        self.pushEncoder = pushEncoder
        self.messageDecoder = messageDecoder
        self.makeWebSocket = makeWebSocket
        self.onConnectionStateChange = onConnectionStateChange
    }

    deinit {
        shouldReconnect = false
        cancelHeartbeat()
        pushes.cancelAllAndInvalidate()
        connectionState = .closed
        channels.removeAll()
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
        print("$$$", #function, connectionState.description)
        guard case .closed = connectionState, shouldReconnect else { return }

        connectionState = .waitingToReconnect

        print("$$$", #function, "before timeout", connectionState.description)

        if let timeout = Self.retryTimeout(attempts: attempts) {
            try await Task.sleep(nanoseconds: NSEC_PER_SEC * UInt64(timeout))
        }

        print("$$$", #function, "after timeout", connectionState.description)

        guard case .waitingToReconnect = connectionState, shouldReconnect else { return }
        connectionState = .preparingToReconnect

        os_log("reconnect", log: .phoenix, type: .debug)

        let ws = try await doMakeWebSocket()
        connectionState = .connecting(ws)

        do {
            try await ws.open(TimeInterval(timeout / NSEC_PER_SEC))

            connectionState = .open(ws)
            reconnectAttempts = 0
            pushes.resume()
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
            "disconnect: oldstate=%{public}@",
            log: .phoenix,
            type: .debug,
            connectionState.description
        )

        shouldReconnect = false
        try await close(
            error: nil,
            timeout: timeout?.nanoseconds ?? self.timeout
        )
    }

    func disconnectImmediately() async throws {
        os_log(
            "disconnect: oldstate=%{public}@",
            log: .phoenix,
            type: .debug,
            connectionState.description
        )

        shouldReconnect = false
        try await close(error: nil, timeout: 1)
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
    func push(_ push: Push) async throws -> Message {
        os_log(
            "push: %@",
            log: .phoenix,
            type: .debug,
            push.description
        )

        return try await pushes.appendAndWait(push)
    }

    func push(_ push: Push) async throws {
        os_log(
            "push: %@",
            log: .phoenix,
            type: .debug,
            push.description
        )

        try await pushes.append(push)
    }

    func makeRef() -> Ref {
        _ref.access { ref in
            let newRef = ref.next
            ref = newRef
            return newRef
        }
    }

    private func flush() {
        precondition(flushTask == nil)

        flushTask = Task { [weak self] in
            guard let self, !Task.isCancelled,
                  let ws = await self.webSocket
            else { return }

            let encoder = self.pushEncoder

            for try await push in self.pushes {
                os_log(
                    "send: %@",
                    log: .phoenix,
                    type: .debug,
                    push.description
                )

                do {
                    try await ws.send(encoder(push))
                    self.pushes.didSend(push)
                } catch {
                    await handleSocketError(error)
                    return // Break out of `Task`
                }

                if Task.isCancelled { break }
            }
        }
    }

    private func cancelFlush() async {
        flushTask?.cancel()
        try? await flushTask?.value
        flushTask = nil
    }

    private func listen() {
        Task { [weak self] in
            guard let self, !Task.isCancelled,
                  let ws = await self.webSocket
            else { return }

            let decoder = self.messageDecoder

            for await msg in ws.messages {
                do {
                    let message = try decoder(msg)
                    guard !self.pushes.didReceive(message)
                    else { continue }

                    // Forward non-reply to correct channel

                } catch {
                    os_log(
                        "message.error: %@",
                        log: .phoenix,
                        type: .error,
                        String(describing: error)
                    )
                }

                if Task.isCancelled { break }
            }
        }
    }

    private func handleSocketError(_ error: Error) async {
        os_log(
            "socket.error: %@",
            log: .phoenix,
            type: .error,
            String(describing: error)
        )

        try? await close(error: error, timeout: timeout)
    }

    private func close(error _: Error?, timeout: UInt64) async throws {
        print("$$$", #function, "before cancelFlush()")
        await cancelFlush()
        print("$$$", #function, "before cancelHeartbeat()")
        cancelHeartbeat()
        print("$$$", #function, "before pushes.stop()")
        pushes.pause()

        let timeout = TimeInterval(nanoseconds: timeout)

        switch connectionState {
        case .waitingToReconnect, .preparingToReconnect, .closed, .closing:
            print("$$$", #function, connectionState.description)
            return

        case let .connecting(ws):
            print("$$$", #function, connectionState.description)
            connectionState = .closing(ws)
            try await ws.close(.normalClosure, timeout)
            connectionState = .closed

        case let .open(ws):
            print("$$$", #function, connectionState.description)
            connectionState = .closing(ws)
            // try await flushPendingMessagesAndWait()
            try await ws.close(.normalClosure, timeout)
            connectionState = .closed
        }
    }
}

extension PhoenixSocket {
    private func scheduleHeartbeat() {
        guard heartbeatTask == nil else { return }

        let interval = heartbeatInterval
        heartbeatTask = Task { [weak self] in
            try await Task.sleep(nanoseconds: interval)
            try await self?.sendHeartbeat()
        }
    }

    private func cancelHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
    }

    private func sendHeartbeat() async throws {
        guard !Task.isCancelled, connectionState.isOpen
        else { return cancelHeartbeat() }

        let task = Task { [weak self] () -> Bool in
            guard !Task.isCancelled, let self
            else { throw CancellationError() }

            let message: Message = try await self.push(
                Push(
                    joinRef: nil,
                    ref: self.makeRef(),
                    topic: "phoenix",
                    event: .heartbeat
                )
            )

            return message.payload["status"] == "ok"
        }

        let timer = DispatchTimer(
            fireAt: .now() + .nanoseconds(Int(timeout))
        ) { task.cancel() }
        defer { timer.invalidate() }

        switch await task.result {
        case let .success(didAck) where didAck:
            heartbeatTask = nil
            scheduleHeartbeat()

        case .success:
            // I think `defer` will wait until handleSocketError()
            // returns, which might be much later.
            timer.invalidate()
            await handleSocketError(PhoenixError.heartbeatTimeout)
            try await reconnect(attempts: reconnectAttempts)

        case let .failure(error):
            // I think `defer` will wait until handleSocketError()
            // returns, which might be much later.
            timer.invalidate()
            print("$$$", #function, "before handleSocketError")
            await handleSocketError(error)
            print("$$$", #function, "after handleSocketError")
            try await reconnect(attempts: reconnectAttempts)
            print("$$$", #function, "after reconnect()")
        }
    }
}

extension PhoenixSocket {
    enum ConnectionState: CustomStringConvertible {
        case closed
        case waitingToReconnect
        case preparingToReconnect
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
            case .preparingToReconnect: return "preparingToReconnect"
            case .connecting: return "connecting"
            case .open: return "open"
            case .closing: return "closing"
            }
        }
    }
}

private extension PhoenixSocket {
    func doMakeWebSocket() async throws -> WebSocket {
        // Do we need to have `onClose` or should we just
        // rely on receiving errors when we try to send
        // messages?
        try await makeWebSocket(
            url,
            .init(), // options
            {}, // onOpen
            { _ in
                Task { [weak self] in
                    guard let self else { return }
                    try? await self.close(error: nil, timeout: self.timeout)
                    try await self.reconnect(attempts: self.reconnectAttempts)
                }
            } // onClose
        )
    }

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
