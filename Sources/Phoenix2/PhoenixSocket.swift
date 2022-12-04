import Collections
import DispatchTimer
import Foundation
import os.log
import Synchronized
import WebSocket

typealias MakeWebSocket =
    (
        Int,
        URL,
        WebSocketOptions,
        @escaping WebSocketOnOpen,
        @escaping WebSocketOnClose
    ) async throws -> WebSocket

final actor PhoenixSocket {
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

    nonisolated private let currentWebSocketID = Locked(0)
    private let makeWebSocket: MakeWebSocket

    private(set) var connectionState: ConnectionState = .closed(connectionAttempts: 0) {
        didSet { onConnectionStateChange(connectionState) }
    }

    private let onConnectionStateChange: (ConnectionState) -> Void

    private(set) var shouldReconnect: Bool = true

    nonisolated var ref: Ref { _ref.access { $0 } }
    private let _ref = Locked(Ref(0))

    private(set) var channels: [Topic: PhoenixChannel] = [:]

    private nonisolated let pushes = PushBuffer()

    private var flushTask: Task<Void, Error>?
    private var listenTask: Task<Void, Error>?
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

        flushTask?.cancel()
        flushTask = nil
        listenTask?.cancel()
        listenTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil

        pushes.cancelAllAndInvalidate()
        connectionState = .closed(connectionAttempts: 0)
        channels.removeAll()
    }

    func connect() async throws {
        guard case .closed = connectionState else { return }
        shouldReconnect = true
        try await doConnect()
    }

    func disconnect(timeout: TimeInterval? = nil) async {
        guard let ws = webSocket else { return }
        await doCloseFromClient(
            id: ws.id,
            timeout: timeout?.nanoseconds ?? self.timeout
        )
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
        assert(flushTask == nil)

        flushTask = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }

            let encoder = self.pushEncoder

            for try await push in self.pushes {
                os_log(
                    "send: %@",
                    log: .phoenix,
                    type: .debug,
                    push.description
                )

                guard let ws = await self.webSocket,
                      !Task.isCancelled
                else { return }

                do {
                    try await ws.send(encoder(push))

                    if Task.isCancelled { return }

                    self.pushes.didSend(push)
                } catch {
                    if Task.isCancelled { return }
                    await doCloseFromServer(id: ws.id, error: error)
                    return // Break out of `Task`
                }

                if Task.isCancelled { return }
            }
        }
    }

    private func cancelFlush() {
        flushTask?.cancel()
        flushTask = nil
    }

    private func listen() {
        assert(listenTask == nil)

        listenTask = Task { [weak self] in
            guard let self, !Task.isCancelled,
                  let ws = await self.webSocket
            else { return }

            let decoder = self.messageDecoder

            for await msg in ws.messages {
                do {
                    let message = try decoder(msg)
                    guard !self.pushes.didReceive(message)
                    else { continue }

                    // TODO: Forward non-reply to correct channel

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

    private func cancelListen() {
        listenTask?.cancel()
        listenTask = nil
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
            else { throw PhoenixError.heartbeatTimeout }

            let message: Message = try await self.push(
                Push(
                    joinRef: nil,
                    ref: self.makeRef(),
                    topic: "phoenix",
                    event: .heartbeat
                )
            )

            guard !Task.isCancelled
            else { throw PhoenixError.heartbeatTimeout }

            return message.payload["status"] == "ok"
        }

        let timer = DispatchTimer(
            fireAt: .now() + .nanoseconds(Int(timeout))
        ) { task.cancel() }

        switch await task.result {
        case let .success(didAck) where didAck:
            timer.invalidate()
            heartbeatTask = nil
            scheduleHeartbeat()

        case .success:
            timer.invalidate()
            guard let ws = self.webSocket else { return }
            await doCloseFromServer(
                id: ws.id,
                error: PhoenixError.heartbeatTimeout
            )
            try await doConnect()

        case let .failure(error):
            timer.invalidate()
            guard let ws = self.webSocket else { return }
            await doCloseFromServer(id: ws.id, error: error)
            try await doConnect()
        }
    }
}

extension PhoenixSocket {
    enum ConnectionState: CustomStringConvertible {
        case closed(connectionAttempts: Int)
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

    /// Connects to the socket. If `attempt` is 0, this is the first
    /// connection attempt. Otherwise, a previous connection failed
    /// and this one will happen after a delay.
    func doConnect() async throws {
        guard case let .closed(attempts) = connectionState,
              shouldReconnect
        else { return }

        connectionState = .waitingToReconnect

        if let timeout = Self.retryDelay(attempts: attempts) {
            try await Task.sleep(nanoseconds: NSEC_PER_SEC * UInt64(timeout))
        }

        guard case .waitingToReconnect = connectionState, shouldReconnect
        else { return }

        connectionState = .preparingToReconnect

        os_log("reconnect", log: .phoenix, type: .debug)

        let ws = try await doMakeWebSocket()
        connectionState = .connecting(ws)

        do {
            try await ws.open(TimeInterval(timeout / NSEC_PER_SEC))

            connectionState = .open(ws)
            pushes.resume()
            flush()
            scheduleHeartbeat()

        } catch {
            connectionState = .closed(connectionAttempts: attempts + 1)
            try await doConnect()
        }
    }

    /// Closes the WebSocket and disables all reconnect logic in
    /// response to the client calling `PhoenixSocket.disconnect()`.
    private func doCloseFromClient(id: WebSocket.ID, timeout: UInt64) async {
        guard let ws = webSocket, ws.id == id else { return }

        let timeout = TimeInterval(nanoseconds: timeout)

        shouldReconnect = false
        pushes.pause()
        cancelFlush()
        cancelListen()
        cancelHeartbeat()

        os_log(
            "disconnect: oldstate=%{public}@",
            log: .phoenix,
            type: .debug,
            connectionState.description
        )

        connectionState = .closing(ws)
        try? await ws.close(timeout: timeout)
        connectionState = .closed(connectionAttempts: 0)
    }

    /// Closes the WebSocket and attempts to reconnect in response
    /// to an error.
    private func doCloseFromServer(
        id: WebSocket.ID,
        error: Error,
        timeout: UInt64? = nil
    ) async {
        let timeout = TimeInterval(nanoseconds: timeout ?? self.timeout)

        func cancelAllInputOutput() {
            pushes.pause(error: error)
            cancelFlush()
            cancelListen()
            cancelHeartbeat()
        }

        switch connectionState {
        case let .connecting(ws) where ws.id == id,
             let .open(ws) where ws.id == id:

            os_log(
                "close: %@",
                log: .phoenix,
                type: .error,
                String(describing: error)
            )

            connectionState = .closing(ws)
            cancelAllInputOutput()
            try? await ws.close(closeCode(from: error), timeout)
            connectionState = .closed(connectionAttempts: 0)
            // TODO: Start reconnection timer

        default:
            break
        }
    }
}

private extension PhoenixSocket {
    func doMakeWebSocket() async throws -> WebSocket {
        let id = currentWebSocketID.access { (id: inout Int) -> Int in
            id += 1
            return id
        }

        return try await makeWebSocket(
            id, // id
            url, // url
            .init(), // options
            {}, // onOpen
            { [id] close in
                Task { [weak self] in
                    guard let self else { return }
                    await self.doCloseFromServer(
                        id: id,
                        error: WebSocketError.closeCodeAndReason(close.code, close.reason)
                    )
                }
            } // onClose
        )
    }

    // Serves the same purpose as `reconnectTimer` in PhoenixJS
    static func retryDelay(attempts: Int) -> TimeInterval? {
        guard attempts > 0 else { return nil }
        guard attempts < 9 else { return 5 }
        return [0.01, 0.05, 0.1, 0.15, 0.2, 0.25, 0.5, 1, 2][attempts]
    }
}

private func closeCode(from error: Error?) -> WebSocketCloseCode {
    guard let error, let wsError = error as? WebSocketError
    else { return .normalClosure }

    switch wsError {
    case let .closeCodeAndReason(closeCode, _):
        return closeCode

    case .invalidURL:
        return .unknown

    case .sendMessageWhileConnecting:
        return .normalClosure
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
