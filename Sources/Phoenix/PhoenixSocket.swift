import AsyncExtensions
import Collections
@preconcurrency import Combine
import Foundation
import JSON
import os.log
import Synchronized
import WebSocket

typealias MakeWebSocket =
    @Sendable (
        Int,
        URL,
        WebSocketOptions,
        @escaping WebSocketOnOpen,
        @escaping WebSocketOnClose
    ) async throws -> WebSocket

typealias ConnectionStatePublisher =
    AnyPublisher<PhoenixSocket.ConnectionState, Never>

final actor PhoenixSocket {
    var webSocket: WebSocket? {
        switch _connectionState.value {
        case let .connecting(ws), let .open(ws), let .closing(ws):
            return ws

        case .waitingToReconnect, .preparingToReconnect, .closed:
            return nil
        }
    }

    nonisolated let url: URL
    nonisolated let timeout: UInt64
    nonisolated let heartbeatInterval: UInt64

    nonisolated let pushEncoder: PushEncoder
    nonisolated let messageDecoder: MessageDecoder

    nonisolated var messages: AsyncStream<Message> { messageSubject.allValues }
    private nonisolated let messageSubject = PassthroughSubject<Message, Never>()

    private nonisolated let currentWebSocketID = Locked(0)
    private let makeWebSocket: MakeWebSocket

    nonisolated var connectionState: ConnectionState {
        _connectionState.value
    }

    nonisolated var onConnectionStateChange: ConnectionStatePublisher {
        _connectionState.eraseToAnyPublisher()
    }

    private nonisolated let _connectionState =
        CurrentValueSubject<
            PhoenixSocket.ConnectionState,
            Never
        >(.closed(connectionAttempts: 0))

    private(set) var shouldReconnect: Bool = true

    nonisolated var ref: Ref { _ref.access { $0 } }
    private let _ref = Locked(Ref(0))

    private(set) var channels: [Topic: PhoenixChannel] = [:]

    private nonisolated let pushes = PushBuffer()
    private nonisolated let tasks = TaskStore()

    init(
        url: URL,
        timeout: TimeInterval = 10,
        heartbeatInterval: TimeInterval = 30,
        pushEncoder: @escaping PushEncoder = Push.encode,
        messageDecoder: @escaping MessageDecoder = Message.decode,
        makeWebSocket: @escaping MakeWebSocket
    ) {
        self.url = url.webSocketURLV2
        self.timeout = timeout.nanoseconds
        self.heartbeatInterval = heartbeatInterval.nanoseconds
        self.pushEncoder = pushEncoder
        self.messageDecoder = messageDecoder
        self.makeWebSocket = makeWebSocket
    }

    deinit {
        shouldReconnect = false

        tasks.cancelAll()
        pushes.cancelAllAndInvalidate()
        channels.removeAll()
    }

    func connect() async {
        guard case .closed = _connectionState.value else { return }
        shouldReconnect = true
        await doConnect()
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
    func channel(
        _ topic: Topic,
        joinPayload: JSON = [:],
        rejoinDelay: [TimeInterval] = [0, 1, 2, 5, 10]
    ) -> PhoenixChannel {
        if let channel = channels[topic] {
            return channel
        } else {
            let channel = PhoenixChannel(
                topic: topic,
                joinPayload: joinPayload,
                rejoinDelay: rejoinDelay,
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
        let channel = channels.removeValue(forKey: topic)
        channel?.leaveImmediately()
    }

    func removeAll() {
        channels.values.forEach { $0.leaveImmediately() }
        channels.removeAll()
    }
}

extension PhoenixSocket {
    func send(_ push: Push) async throws {
        os_log(
            "push: %@",
            log: .phoenix,
            type: .debug,
            push.description
        )

        try await pushes.append(push)
    }

    func request(_ push: Push) async throws -> Message {
        os_log(
            "push: %@",
            log: .phoenix,
            type: .debug,
            push.description
        )

        return try await pushes.appendAndWait(push)
    }

    func makeRef() -> Ref {
        _ref.access { ref in
            let newRef = ref.next
            ref = newRef
            return newRef
        }
    }

    private func flush() {
        let task = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }

            let encoder = pushEncoder

            for try await push in pushes {
                guard let ws = await webSocket,
                      !Task.isCancelled
                else { return }

                do {
                    if let channel = await channels[push.topic] {
                        guard await channel.prepareToSend(push) else {
                            pushes.putBack(push)
                            await Task.yield()
                            continue
                        }
                    } else {
                        push.prepareToSend(ref: await makeRef())
                    }

                    try await ws.send(encoder(push))

                    if Task.isCancelled { return }

                    os_log(
                        "send: %@",
                        log: .phoenix,
                        type: .debug,
                        push.description
                    )

                    pushes.didSend(push)
                } catch {
                    if Task.isCancelled { return }
                    await doCloseFromServer(id: ws.id, error: error)
                    return // Break out of `Task`
                }

                if Task.isCancelled { return }
            }
        }

        tasks.insert(task, forKey: "flush")
    }

    private func listen() {
        let task = Task { [weak self] in
            guard let self, !Task.isCancelled,
                  let ws = await self.webSocket
            else { return }

            let decoder = self.messageDecoder

            for await msg in ws.messages {
                do {
                    let message = try decoder(msg)

                    _ = self.pushes.didReceive(message)

                    // NOTE: In the case a channel receives
                    // `Event.close`, it will remove itself from
                    // `channels`. To avoid any potential problems
                    // we make a copy of the channels before
                    // iterating over it.
                    let channels = Array(await channels.values)
                    for channel in channels {
                        await channel.receive(message)
                    }

                    messageSubject.send(message)
                } catch {
                    os_log(
                        "message.error: %@",
                        log: .phoenix,
                        type: .error,
                        String(describing: error)
                    )

                    if Task.isCancelled { return }
                    await doCloseFromServer(id: ws.id, error: error)
                }

                if Task.isCancelled { break }
            }
        }

        tasks.insert(task, forKey: "listen")
    }
}

extension PhoenixSocket {
    private func scheduleHeartbeat() {
        let interval = heartbeatInterval
        let task = Task { [weak self] in
            try await Task.sleep(nanoseconds: interval)
            try await self?.sendHeartbeat()
        }

        tasks.insert(task, forKey: "heartbeat")
    }

    private func sendHeartbeat() async throws {
        guard case let .open(_ws) = _connectionState.value,
              !Task.isCancelled
        else { return tasks.cancel(forKey: "heartbeat") }

        let id = _ws.id

        let didSucceed = await withThrowingTaskGroup(of: Bool.self) { group in
            group.addTask { [weak self] in
                guard !Task.isCancelled, let self
                else { throw TimeoutError() }

                let push = Push(topic: "phoenix", event: .heartbeat)
                let message: Message = try await self.request(push)

                guard !Task.isCancelled
                else { throw TimeoutError() }

                return message.payload["status"] == "ok"
            }

            group.addTask { [weak self] in
                guard let timeout = self?.timeout else { return false }
                try await Task.sleep(nanoseconds: timeout)
                return false
            }

            let result = await group.nextResult()
            group.cancelAll()

            switch result {
            case .success(true): return true
            default: return false
            }
        }

        // If the heartbeat returns after the sending WebSocket
        // has disconnected, then ignore it.
        guard let ws = webSocket, ws.id == id, !Task.isCancelled
        else { return }

        if didSucceed {
            tasks.cancel(forKey: "heartbeat")
            scheduleHeartbeat()
        } else {
            await doCloseFromServer(
                id: ws.id,
                error: TimeoutError()
            )
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
    func doConnect() async {
        guard case let .closed(attempts) = _connectionState.value,
              shouldReconnect, !Task.isCancelled
        else { return }

        _connectionState.value = .waitingToReconnect

        do {
            if let timeout = Self.reconnectDelay(attempts: attempts) {
                try await Task.sleep(nanoseconds: NSEC_PER_SEC * UInt64(timeout))
            }

            guard case .waitingToReconnect = _connectionState.value,
                  shouldReconnect
            else { return }

            _connectionState.value = .preparingToReconnect

            os_log("connect", log: .phoenix, type: .debug)

            let ws = try await doMakeWebSocket()
            _connectionState.value = .connecting(ws)

            try await ws.open()

            try Task.checkCancellation()

            _connectionState.value = .open(ws)
            pushes.resume()
            listen()
            flush()
            scheduleHeartbeat()

        } catch {
            _connectionState.value = .closed(connectionAttempts: attempts + 1)
            await doConnect()
        }
    }

    /// Closes the WebSocket and disables all reconnect logic in
    /// response to the client calling `PhoenixSocket.disconnect()`.
    private func doCloseFromClient(id: WebSocket.ID, timeout: UInt64) async {
        guard let ws = webSocket, ws.id == id else { return }

        let timeout = TimeInterval(nanoseconds: timeout)

        shouldReconnect = false
        pushes.pause()
        tasks.cancelAll()

        os_log(
            "disconnect: oldstate=%{public}@",
            log: .phoenix,
            type: .debug,
            _connectionState.value.description
        )

        _connectionState.value = .closing(ws)
        try? await ws.close(timeout: timeout)
        _connectionState.value = .closed(connectionAttempts: 0)
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
            tasks.cancelAll()
        }

        switch _connectionState.value {
        case let .connecting(ws) where ws.id == id,
             let .open(ws) where ws.id == id:

            os_log(
                "close: %@",
                log: .phoenix,
                type: .error,
                String(describing: error)
            )

            _connectionState.value = .closing(ws)
            cancelAllInputOutput()
            try? await ws.close(closeCode(from: error), timeout)
            _connectionState.value = .closed(connectionAttempts: 0)

            let connectTask = Task.detached { [weak self] in
                await self?.doConnect()
            }
            tasks.add(connectTask)

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
                    guard let self, !Task.isCancelled else { return }
                    await self.doCloseFromServer(
                        id: id,
                        error: WebSocketError.closeCodeAndReason(
                            close.code, close.reason
                        )
                    )
                }
            } // onClose
        )
    }

    // Serves the same purpose as `reconnectTimer` in PhoenixJS
    static func reconnectDelay(attempts: Int) -> TimeInterval? {
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
