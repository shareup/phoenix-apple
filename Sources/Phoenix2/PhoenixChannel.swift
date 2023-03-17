import AsyncExtensions
import Combine
import Foundation
import os.log
import Synchronized

private typealias JoinFuture = AsyncExtensions.Future<(Ref, Payload)>
private typealias LeaveFuture = AsyncExtensions.Future<Void>

private typealias MessagesSubject = PassthroughSubject<Message, Never>

final class PhoenixChannel: @unchecked Sendable {
    let topic: Topic
    let joinPayload: Payload

    var messages: MessagesPublisher { messagesSubject.eraseToAnyPublisher() }

    var isUnjoined: Bool { state.access { $0.isUnjoined } }
    var isJoining: Bool { state.access { $0.isJoining } }
    var isJoined: Bool { state.access { $0.isJoined } }

    private let rejoinDelay: [TimeInterval]
    private let socket: PhoenixSocket
    private let state: Locked<State>
    private let messagesSubject = MessagesSubject()
    private let tasks = TaskStore()

    init(
        topic: Topic,
        joinPayload: Payload = [:],
        rejoinDelay: [TimeInterval] = [0, 1, 2, 5, 10],
        socket: PhoenixSocket
    ) {
        self.topic = topic
        self.joinPayload = joinPayload
        self.rejoinDelay = rejoinDelay
        self.socket = socket
        self.state = Locked(.init(rejoinDelay: rejoinDelay))

        state.access { state in
            state.subscribeToStateChange(
                socket: socket,
                block: onSocketConnectionChange
            )
        }
    }

    deinit {
        tasks.cancelAll()
    }

    @discardableResult
    func join(timeout: TimeInterval? = nil) async throws -> Payload {
        let timeout = timeout ?? TimeInterval(nanoseconds: socket.timeout)
        return try await rejoin(timeout: timeout)
    }

    func leave(timeout: TimeInterval? = nil) async throws {
        tasks.cancel(forKey: "rejoin")

        let leave = state.access { state in
            state.leave(
                topic: topic,
                socket: socket,
                timeout: timeout ?? TimeInterval(nanoseconds: socket.timeout)
            )
        }

        try? await leave()
        let future = state.access { $0.didLeave() }
        os_log(
            "leave: channel=%{public}@",
            log: .phoenix,
            type: .debug,
            topic
        )
        future?.resolve()
    }

    func prepareToSend(_ push: Push) async -> Bool {
        precondition(push.topic == topic)

        guard let joinRef = state.access({ $0.joinRef })
        else { return false }

        push.prepareToSend(ref: await socket.makeRef(), joinRef: joinRef)
        return true
    }

    func receive(_ message: Message) {
        guard topic == message.topic else { return }

        let sendMessage: (() -> Void)? = state.access { state in
            switch state.connection {
            case let .joined(joinRef, _):
                if message.joinRef == joinRef {
                    return { self.messagesSubject.send(message) }
                } else {
                    os_log(
                        "channel outdated message: joinRef=%d message=%d",
                        log: .phoenix,
                        type: .debug,
                        Int(joinRef.rawValue),
                        Int(message.joinRef?.rawValue ?? 0)
                    )
                    return nil
                }

            case .unjoined, .errored, .joining, .leaving, .left:
                return { self.messagesSubject.send(message) }
            }
        }

        sendMessage?()
    }
}

private extension PhoenixChannel {
    var onSocketConnectionChange: (PhoenixSocket.ConnectionState) -> Void {
        { [weak self] (connectionState: PhoenixSocket.ConnectionState) in
            guard let self else { return }

            switch connectionState {
            case .closed:
                let onClose = self.state.access { $0.timedOut() }
                onClose()
                self.scheduleRejoinIfPossible()

            case .open:
                // TODO: rejoin
                break

            case .waitingToReconnect, .preparingToReconnect,
                 .connecting, .closing:
                break
            }
        }
    }

    @discardableResult
    func rejoin(timeout: TimeInterval) async throws -> Payload {
        let join = state.access { state in
            state.rejoin(
                topic: topic,
                payload: joinPayload,
                socket: socket,
                timeout: timeout
            )
        }

        do {
            let (ref, reply) = try await join()
            let future = state.access { $0.didJoin(ref: ref, reply: reply) }
            tasks.cancel(forKey: "rejoin")

            os_log(
                "join: channel=%{public}@",
                log: .phoenix,
                type: .debug,
                topic
            )

            future?.resolve((ref, reply))
            return reply
        } catch {
            state.access { $0.didFailJoin() }?.fail(error)
            tasks.cancel(forKey: "rejoin")

            os_log(
                "join: channel=%{public}@ error=%{public}@",
                log: .phoenix,
                type: .error,
                topic,
                String(describing: error)
            )

            scheduleRejoinIfPossible(timeout: timeout)

            throw error
        }
    }

    func scheduleRejoinIfPossible(timeout: TimeInterval? = nil) {
        let timeout = timeout ?? TimeInterval(nanoseconds: socket.timeout)

        tasks.storedNewTask(key: "rejoin") { [weak self] in
            try Task.checkCancellation()
            try await self?.rejoin(timeout: timeout)
        }
    }
}

private struct State: @unchecked Sendable {
    var connection: Connection
    var rejoinAttempts: Int
    var rejoinDelay: [TimeInterval]
    var socketStateChangeSubscription: AnyCancellable?

    var shouldRejoin: Bool {
        if case .left = connection {
            return false
        } else {
            return true
        }
    }

    var joinRef: Ref? {
        switch connection {
        case .unjoined, .errored, .joining, .leaving, .left:
            return nil

        case let .joined(ref, _):
            return ref
        }
    }

    var isUnjoined: Bool {
        guard case .unjoined = connection else { return false }
        return true
    }

    var isJoining: Bool {
        guard case .joining = connection else { return false }
        return true
    }

    var isJoined: Bool {
        guard case .joined = connection else { return false }
        return true
    }

    enum Connection: CustomStringConvertible {
        case unjoined
        case errored
        case joined(Ref, reply: Payload)
        case joining(JoinFuture)
        case leaving(LeaveFuture)
        case left

        var description: String {
            switch self {
            case .errored: "errored"
            case .joined: "joined"
            case .joining: "joining"
            case .leaving: "leaving"
            case .left: "left"
            case .unjoined: "unjoined"
            }
        }
    }

    init(
        connection: Connection = .unjoined,
        rejoinAttempts: Int = 0,
        rejoinDelay: [TimeInterval],
        socketStateChangeSubscription: AnyCancellable? = nil
    ) {
        self.connection = connection
        self.rejoinAttempts = rejoinAttempts
        self.rejoinDelay = rejoinDelay
        self.socketStateChangeSubscription = socketStateChangeSubscription
    }

    mutating func subscribeToStateChange(
        socket: PhoenixSocket,
        block: @escaping (PhoenixSocket.ConnectionState) -> Void
    ) {
        precondition(socketStateChangeSubscription == nil)
        socketStateChangeSubscription = socket
            .onConnectionStateChange
            .sink(receiveValue: block)
    }

    mutating func rejoin(
        topic: Topic,
        payload: Payload,
        socket: PhoenixSocket,
        timeout: TimeInterval
    ) -> () async throws -> (Ref, Payload) {
        typealias E = PhoenixError

        switch connection {
        case .errored, .unjoined:
            let future = JoinFuture()
            connection = .joining(future)

            let attempt = rejoinAttempts
            rejoinAttempts += 1
            let delay = self.delay(for: attempt)

            return {
                try await delay()

                let push = Push(
                    topic: topic,
                    event: .join,
                    payload: payload,
                    timeout: Date(timeIntervalSinceNow: timeout)
                )

                let message: Message = try await socket.push(push)
                let (ref, isOk, payload) = try message.refAndReply

                guard isOk else {
                    throw E.joinError(message.error ?? "unknown")
                }

                return (ref, payload)
            }

        case let .joined(ref, reply):
            return { (ref, reply) }

        case let .joining(future):
            return { return try await future.value }

        case .leaving, .left:
            return { throw PhoenixError.leavingChannel }
        }
    }

    mutating func didJoin(ref: Ref, reply: Payload) -> JoinFuture? {
        switch connection {
        case .unjoined, .errored, .joined, .leaving, .left:
            return nil

        case let .joining(future):
            rejoinAttempts = 0
            connection = .joined(ref, reply: reply)
            return future
        }
    }

    mutating func didFailJoin() -> JoinFuture? {
        switch connection {
        case .unjoined, .errored, .joined, .leaving, .left:
            return nil

        case let .joining(future):
            connection = .errored
            return future
        }
    }

    mutating func leave(
        topic: Topic,
        socket: PhoenixSocket,
        timeout: TimeInterval
    ) -> () async throws -> Void {
        func doLeave() async throws {
            let push = Push(
                topic: topic,
                event: .leave,
                timeout: Date(timeIntervalSinceNow: timeout)
            )
            let _: Message = try await socket.push(push)
        }

        switch connection {
        case .errored, .left, .unjoined:
            connection = .left
            return {}

        case let .joining(join):
            connection = .leaving(LeaveFuture())

            return {
                join.fail(CancellationError())
                try await doLeave()
            }

        case let .leaving(leave):
            return { try await leave.value }

        case .joined:
            connection = .leaving(LeaveFuture())
            return doLeave
        }
    }

    mutating func didLeave() -> LeaveFuture? {
        switch connection {
        case .unjoined, .errored, .joined, .joining, .left:
            connection = .left
            return nil

        case let .leaving(future):
            connection = .left
            return future
        }
    }

    mutating func timedOut() -> () -> Void {
        switch connection {
        case .unjoined, .errored, .joined:
            connection = .errored
            return {}

        case let .joining(future):
            connection = .errored
            return { future.fail(TimeoutError()) }

        case let .leaving(future):
            connection = .errored
            return { future.resolve() }

        case .left:
            return {}
        }
    }

    func delay(
        for attempt: Int
    ) -> @Sendable () async throws -> Void {
        let delays = rejoinDelay
        let delay = delays[min(attempt, delays.count - 1)]
        return { try await Task.sleep(nanoseconds: delay.nanoseconds) }
    }
}
