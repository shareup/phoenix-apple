import AsyncExtensions
import Combine
import DispatchTimer
import Foundation
import os.log
import Synchronized
import WebSocket
import WebSocketProtocol

private typealias ConnectFuture = AsyncExtensions.Future<Void>

public final class Socket {
    public typealias Output = Socket.Message
    public typealias Failure = Never

    public typealias ReconnectTimeInterval = (Int) -> DispatchTimeInterval

    private let lock = RecursiveLock()
    private func sync<T>(_ block: () throws -> T) rethrows -> T { try lock.locked(block) }

    private let encoder: OutgoingMessageEncoder
    private let decoder: IncomingMessageDecoder

    private let subject = PassthroughSubject<Output, Failure>()
    private var shouldReconnect = true
    private var webSocketSubscriber: AnyCancellable?
    private var channels = [Topic: Channel]()

    private var connectFuture: ConnectFuture?

    #if DEBUG
        private var state: State = .closed { didSet { onStateChange?(state) } }
        internal var onStateChange: ((State) -> Void)?
    #else
        private var state: State = .closed
    #endif

    public var joinedChannels: [Channel] {
        sync { Array(self.channels.values) }
    }

    private var pending: [Push] = []
    var pendingPushes: [Push] { sync { pending } } // For testing

    public let url: URL
    public let timeout: DispatchTimeInterval

    private let notifySubjectQueue: DispatchQueue
    private let backgroundQueue = DispatchQueue(
        label: "app.shareup.phoenix.socket.backgroundqueue",
        qos: .default,
        target: DispatchQueue.backgroundQueue
    )

    private let refGenerator: Ref.Generator

    var currentRef: Ref { refGenerator.current }
    func advanceRef() -> Ref { refGenerator.advance() }

    private let heartbeatPush = Push(topic: "phoenix", event: .heartbeat)
    private var pendingHeartbeatRef: Ref?
    private var heartbeatTimer: DispatchTimer?

    public static let defaultTimeout: DispatchTimeInterval = .seconds(10)
    public static let defaultHeartbeatInterval: DispatchTimeInterval = .seconds(30)
    public let heartbeatInterval: DispatchTimeInterval

    public var maximumMessageSize: Int = 1024 * 1024 {
        didSet { sync {
            state.webSocket?.maximumMessageSize = maximumMessageSize
        } }
    }

    // https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/js/phoenix.js#L790
    public var reconnectTimeInterval: ReconnectTimeInterval =
        { (attempt: Int) -> DispatchTimeInterval in
            let milliseconds = [10, 50, 100, 150, 200, 250, 500, 1000, 2000, 5000]
            switch attempt {
            case 0:
                assertionFailure("`attempt` should start at 1")
                return .milliseconds(milliseconds[5])
            case 1 ..< milliseconds.count:
                return .milliseconds(milliseconds[attempt - 1])
            default:
                return .milliseconds(milliseconds[milliseconds.count - 1])
            }
        }

    private var _reconnectAttempts: Int = 0
    var reconnectAttempts: Int {
        get { sync { _reconnectAttempts } }
        set { sync { _reconnectAttempts = newValue } }
    }

    var isClosed: Bool { sync {
        guard case .closed = state else { return false }
        return true
    } }

    var isConnecting: Bool { sync {
        guard case .connecting = state else { return false }
        return true
    } }

    var isOpen: Bool { sync {
        guard case .open = state else { return false }
        return true
    } }

    var isClosing: Bool { sync {
        guard case .closing = state else { return false }
        return true
    } }

    var connectionState: String { sync { state.description } }

    public init(
        url: URL,
        timeout: DispatchTimeInterval = Socket.defaultTimeout,
        heartbeatInterval: DispatchTimeInterval = Socket.defaultHeartbeatInterval,
        customEncoder: OutgoingMessageEncoder? = nil,
        customDecoder: IncomingMessageDecoder? = nil,
        publisherQueue: DispatchQueue = .global()
    ) {
        self.timeout = timeout
        self.heartbeatInterval = heartbeatInterval
        refGenerator = Ref.Generator()
        self.url = Socket.webSocketURLV2(url: url)
        encoder = customEncoder ?? { try $0.encoded() }
        decoder = customDecoder ?? IncomingMessage.init
        notifySubjectQueue = DispatchQueue(
            label: "app.shareup.phoenix.socket.subjectqueue",
            qos: .default,
            autoreleaseFrequency: .workItem,
            target: publisherQueue
        )
    }

    init(
        url: URL,
        timeout: DispatchTimeInterval = Socket.defaultTimeout,
        heartbeatInterval: DispatchTimeInterval = Socket.defaultHeartbeatInterval,
        refGenerator: Ref.Generator,
        customEncoder: OutgoingMessageEncoder? = nil,
        customDecoder: IncomingMessageDecoder? = nil,
        publisherQueue: DispatchQueue = .global()
    ) {
        self.timeout = timeout
        self.heartbeatInterval = heartbeatInterval
        self.refGenerator = refGenerator
        self.url = Socket.webSocketURLV2(url: url)
        encoder = customEncoder ?? { try $0.encoded() }
        decoder = customDecoder ?? IncomingMessage.init
        notifySubjectQueue = DispatchQueue(
            label: "app.shareup.phoenix.socket.subjectqueue",
            qos: .default,
            autoreleaseFrequency: .workItem,
            target: publisherQueue
        )
    }

    deinit {
        disconnect()
        sync {
            webSocketSubscriber?.cancel()
            webSocketSubscriber = nil
            state.webSocket?.close()
        }
    }
}

// MARK: Phoenix socket URL

extension Socket {
    static func webSocketURLV2(url original: URL) -> URL {
        original
            .appendingPathComponent("websocket")
            .appendingQueryItems(["vsn": "2.0.0"])
    }
}

// MARK: Publisher

extension Socket: Publisher {
    public func receive<S>(subscriber: S)
        where S: Combine.Subscriber, Failure == S.Failure, Output == S.Input
    {
        subject.receive(subscriber: subscriber)
    }
}

// MARK: ConnectablePublisher

extension Socket: ConnectablePublisher {
    private struct Canceller: Cancellable {
        weak var socket: Socket?

        func cancel() {
            socket?.disconnect()
        }
    }

    @discardableResult
    public func connect() -> Cancellable {
        sync {
            self.shouldReconnect = true

            switch state {
            case .closed:
                let ws = WebSocket(url: url, timeoutIntervalForRequest: 2)
                ws.maximumMessageSize = maximumMessageSize
                self.state = .connecting(ws)
                ws.connect()

                let subject = self.subject
                notifySubjectQueue.async { subject.send(.connecting) }

                self.webSocketSubscriber = makeWebSocketSubscriber(with: ws)
                cancelHeartbeatTimer()
                createHeartbeatTimer()

                return Canceller(socket: self)
            case .connecting, .open:
                // NOOP
                return Canceller(socket: self)
            case .closing:
                // let the reconnect logic handle this case
                return Canceller(socket: self)
            }
        }
    }

    public func connect() async throws {
        let next = sync { () -> () -> ConnectFuture? in
            self.shouldReconnect = true

            switch state {
            case .closed:
                connectFuture?.fail(CancellationError())
                let fut = ConnectFuture()
                connectFuture = fut

                let ws = WebSocket(url: url, timeoutIntervalForRequest: 2)
                ws.maximumMessageSize = maximumMessageSize
                self.state = .connecting(ws)

                notifySubjectQueue.async { [subject] in
                    subject.send(.connecting)
                }

                self.webSocketSubscriber = makeWebSocketSubscriber(with: ws)
                cancelHeartbeatTimer()
                createHeartbeatTimer()

                return {
                    ws.connect()
                    return fut
                }

            case .connecting:
                let fut = connectFuture
                return { fut }

            case .open:
                return { nil }

            case .closing:
                let fut = connectFuture
                return { fut }
            }
        }

        guard let fut = next() else { return }

        do {
            try await fut.value
        } catch let error where error is CancellationError {
            // This is what the `Canceller` does in the original
            // implementation of `connect()`.
            disconnect()
            throw error
        }
    }

    public func disconnect() {
        os_log(
            "socket.disconnect: oldstate=%{public}@",
            log: .phoenix,
            type: .debug,
            state.description
        )

        // Calling `Channel.leave()` inside `sync` can cause a deadlock.
        let channels: [Channel] = sync {
            let channels = Array(self.channels.values)
            self.channels.removeAll()
            return channels
        }
        channels.forEach { $0.leave() }

        sync {
            shouldReconnect = false
            cancelHeartbeatTimer()

            let fut = connectFuture
            connectFuture = nil
            fut?.fail(CancellationError())

            switch state {
            case .closed, .closing:
                break
            case let .open(ws), let .connecting(ws):
                state = .closing(ws)

                let subject = self.subject
                notifySubjectQueue.async { subject.send(.closing) }

                ws.close()
            }
        }
    }

    @discardableResult
    public func disconnectAndWait(
        timeout: DispatchTimeInterval = .seconds(1)
    ) -> DispatchTimeoutResult {
        guard isClosed == false else {
            // `disconnect()` does additional cleanup regardless
            // of the current state. We could be in a
            // "closed-but-reconnecting" state, which
            // `disconnect()` handles.
            disconnect()
            return .success
        }

        let semaphore = DispatchSemaphore(value: 0)
        let subscription = sink { value in
            guard case .close = value else { return }
            semaphore.signal()
        }
        defer { subscription.cancel() }
        disconnect()
        let result = semaphore.wait(timeout: .now() + timeout)

        os_log(
            "socket.disconnectAndWait: result=%{public}@",
            log: .phoenix,
            type: .debug,
            result.description
        )

        return result
    }

    @discardableResult
    private func reconnectIfPossible() -> Bool {
        sync {
            if shouldReconnect {
                _reconnectAttempts += 1
                let deadline = DispatchTime.now()
                    .advanced(by: reconnectTimeInterval(_reconnectAttempts))
                backgroundQueue.asyncAfter(deadline: deadline) { [weak self] in
                    guard let self else { return }
                    guard self.lock.locked({ self.shouldReconnect }) else { return }
                    self.connect()
                }
                return true
            } else {
                return false
            }
        }
    }
}

// MARK: Channel

public extension Socket {
    func join(_ channel: Channel) {
        channel.join()
    }

    func join(_ channel: Channel) async throws -> Payload {
        try await channel.join()
    }

    func join(_ topic: Topic, payload: Payload = [:]) -> Channel {
        sync {
            let _channel = channel(topic, payload: payload)
            _channel.join()
            return _channel
        }
    }

    func channel(_ topic: Topic, payload: Payload = [:]) -> Channel {
        sync {
            if let channel = channels[topic] {
                return channel
            }

            let channel = Channel(
                topic: topic,
                joinPayload: payload,
                socket: self
            )

            channels[topic] = channel

            return channel
        }
    }

    func leave(_ topic: Topic) {
        leave(channel(topic))
    }

    func leave(_ channel: Channel) {
        channel.leave()
    }

    func leave(_ topic: Topic) async throws {
        let channel = channel(topic)
        try await leave(channel)
    }

    func leave(_ channel: Channel) async throws {
        try await channel.leave()
    }

    @discardableResult
    private func removeChannel(for topic: Topic) -> Channel? {
        sync { channels.removeValue(forKey: topic) }
    }
}

// MARK: Push event

public extension Socket {
    func push(topic: Topic, event: PhxEvent) {
        push(topic: topic, event: event, payload: [:])
    }

    func push(topic: Topic, event: PhxEvent, payload: Payload) {
        push(topic: topic, event: event, payload: payload) { _ in }
    }

    func push(
        topic: Topic,
        event: PhxEvent,
        payload: Payload = [:],
        callback: @escaping Callback
    ) {
        let thePush = Socket.Push(
            topic: topic,
            event: event,
            payload: payload,
            callback: callback
        )

        sync {
            pending.append(thePush)
        }

        flushAsync()
    }
}

// MARK: Flush

extension Socket {
    private func flush() {
        sync {
            guard case .open = state else { return }

            guard let push = pending.first else { return }
            self.pending = Array(self.pending.dropFirst())

            let ref = advanceRef()
            let message = OutgoingMessage(push, ref: ref)

            send(message) { error in
                if error == nil {
                    self.flushAsync()
                }
                push.asyncCallback(error)
            }
        }
    }

    private func flushAsync() {
        backgroundQueue.async { self.flush() }
    }
}

// MARK: Send

extension Socket {
    func send(_ message: OutgoingMessage) {
        send(message, completionHandler: { _ in })
    }

    func send(_ message: OutgoingMessage, completionHandler: @escaping Callback) {
        do {
            switch try encoder(message) {
            case let .binary(data):
                send(data, completionHandler: completionHandler)
            case let .text(text):
                send(text, completionHandler: completionHandler)
            }
        } catch {
            completionHandler(Error.couldNotSerializeOutgoingMessage(message))
        }
    }

    func send(_ string: String) {
        send(string) { _ in }
    }

    func send(_ string: String, completionHandler: @escaping Callback) {
        sync {
            switch state {
            case let .open(ws):
                ws.send(string) { error in
                    if let error {
                        os_log(
                            "socket.send.text.error: error=%s",
                            log: .phoenix,
                            type: .error,
                            String(describing: error)
                        )

                        self.state = .closing(ws) // TODO: write a test to prove this works
                        ws.close(WebSocketCloseCode.abnormalClosure)
                    }

                    completionHandler(error)
                }
            default:
                completionHandler(Socket.Error.notOpen)

                let subject = self.subject
                notifySubjectQueue.async { subject.send(.close) }
            }
        }
    }

    func send(_ data: Data) {
        send(data, completionHandler: { _ in })
    }

    func send(_ data: Data, completionHandler: @escaping Callback) {
        sync {
            switch state {
            case let .open(ws):
                ws.send(data) { error in
                    if let error {
                        os_log(
                            "socket.send.data.error: error=%s",
                            log: .phoenix,
                            type: .error,
                            String(describing: error)
                        )

                        self.state = .closing(ws) // TODO: write a test to prove this works
                        ws.close(WebSocketCloseCode.abnormalClosure)
                    }

                    completionHandler(error)
                }
            default:
                completionHandler(Socket.Error.notOpen)

                let subject = self.subject
                notifySubjectQueue.async { subject.send(.close) }
            }
        }
    }
}

// MARK: Heartbeat

extension Socket {
    typealias HeartbeatSuccessHandler = () -> Void

    func sendHeartbeat(_ onSuccess: HeartbeatSuccessHandler? = nil) {
        let msg: OutgoingMessage? = sync {
            guard pendingHeartbeatRef == nil else {
                heartbeatTimeout()
                return nil
            }

            guard case .open = state else { return nil }

            let pendingHeartbeatRef = advanceRef()
            self.pendingHeartbeatRef = pendingHeartbeatRef
            return OutgoingMessage(heartbeatPush, ref: pendingHeartbeatRef)
        }

        guard let message = msg else { return }

        send(message) { error in
            if error != nil {
                self.heartbeatTimeout()
            } else if let onSuccess {
                onSuccess()
            }
        }
    }

    func heartbeatTimeout() {
        sync {
            os_log(
                "socket.heartbeatTimeout: oldstate=%{public}@",
                log: .phoenix,
                type: .debug,
                state.description
            )

            self.pendingHeartbeatRef = nil

            switch state {
            case .closed, .closing:
                // NOOP
                return
            case let .open(ws), let .connecting(ws):
                ws.close()
                // TODO: shouldn't this be an errored state?
                self.state = .closed

                let subject = self.subject
                notifySubjectQueue.async { subject.send(.close) }

                reconnectIfPossible()
            }
        }
    }

    func cancelHeartbeatTimer() {
        heartbeatTimer = nil
    }

    func createHeartbeatTimer() {
        heartbeatTimer = DispatchTimer(heartbeatInterval, repeat: true) { [weak self] in
            self?.sendHeartbeat()
        }
    }
}

// MARK: WebSocket subscriber

extension Socket {
    typealias WebSocketOutput = Result<WebSocketMessage, Swift.Error>
    typealias WebSocketFailure = Swift.Error

    func makeWebSocketSubscriber(with webSocket: WebSocket) -> AnyCancellable {
        let value: (WebSocketOutput) -> Void = { [weak self] in self?.receive(value: $0) }
        let completion: (Subscribers.Completion<Swift.Error>) -> Void = { [weak self] in
            self?.receive(completion: $0)
        }

        return webSocket.sink(receiveCompletion: completion, receiveValue: value)
    }

    private func receive(value: WebSocketOutput) {
        let subject = subject

        func handleBinaryOrTextMessage(_ rawMessage: RawIncomingMessage) {
            let subject = self.subject
            do {
                let msg = try decoder(rawMessage)
                sync {
                    switch msg.event {
                    case .reply
                        where pendingHeartbeatRef != nil && msg.ref == pendingHeartbeatRef:
                        self.pendingHeartbeatRef = nil
                    case .close:
                        removeChannel(for: msg.topic)
                        notifySubjectQueue.async { subject.send(.incomingMessage(msg)) }
                    default:
                        notifySubjectQueue.async { subject.send(.incomingMessage(msg)) }
                    }
                }
            } catch {
                os_log(
                    "socket.receive could not decode message: message=%s error=%s",
                    log: .phoenix,
                    type: .error,
                    rawMessage.description,
                    error.localizedDescription
                )

                notifySubjectQueue.async {
                    subject.send(.unreadableMessage(rawMessage.description))
                }
            }
        }

        switch value {
        case let .failure(error):
            os_log(
                "socket.receive.failure: error=%s",
                log: .phoenix,
                type: .error,
                String(describing: error)
            )

            notifySubjectQueue.async { subject.send(.websocketError(error)) }
        case let .success(message):
            switch message {
            case .open:
                sync {
                    _reconnectAttempts = 0

                    switch state {
                    case .closed, .closing:
                        os_log(
                            "socket.receive open in wrong state: state=%{public}@",
                            log: .phoenix,
                            type: .error,
                            state.description
                        )

                        connectFuture?.resolve()
                        connectFuture = nil
                        return
                    case .open:
                        connectFuture?.resolve()
                        connectFuture = nil
                        return
                    case let .connecting(ws):
                        self.state = .open(ws)
                        notifySubjectQueue.async { subject.send(.open) }
                        connectFuture?.resolve()
                        connectFuture = nil
                        flushAsync()
                    }
                }
            case let .binary(data):
                handleBinaryOrTextMessage(.binary(data))
            case let .text(text):
                handleBinaryOrTextMessage(.text(text))
            }
        }
    }

    private func receive(completion _: Subscribers.Completion<WebSocketFailure>) {
        sync {
            switch state {
            case .closed:
                connectFuture?.resolve()
                connectFuture = nil

            case .open, .connecting, .closing:
                self.state = .closed
                self.webSocketSubscriber = nil

                let subject = self.subject
                notifySubjectQueue.async { subject.send(.close) }

                if !reconnectIfPossible() {
                    connectFuture?.resolve()
                    connectFuture = nil
                }
            }
        }
    }
}
