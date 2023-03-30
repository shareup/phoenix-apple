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

    var isErrored: Bool { state.access { $0.isErrored } }
    var isJoining: Bool { state.access { $0.isJoining } }
    var isJoined: Bool { state.access { $0.isJoined } }
    var isUnjoined: Bool { state.access { $0.isUnjoined } }

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
        self.socket = socket
        state = Locked(.init(rejoinDelay: rejoinDelay))

        watchSocketConnection()
    }

    deinit {
        tasks.cancelAll()
    }

    @discardableResult
    func join(timeout: TimeInterval? = nil) async throws -> Payload {
        state.access { $0.prepareToJoin() }
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
        tasks.cancel(forKey: "socketConnection")
        os_log(
            "leave: channel=%{public}@",
            log: .phoenix,
            type: .debug,
            topic
        )
        future?.resolve()
    }

    @discardableResult
    func push(
        _ event: String,
        payload: Payload = [:],
        timeout: TimeInterval? = nil
    ) async throws -> Payload {
        let timeout = timeout ?? TimeInterval(nanoseconds: socket.timeout)
        let push = Push(
            topic: topic,
            event: .custom(event),
            payload: payload,
            timeout: Date(timeIntervalSinceNow: timeout)
        )

        let response: Message = try await socket.push(push)
        let reply = try response.reply

        guard reply.isOk else {
            throw PhoenixError.pushError(topic, event, reply.payload)
        }

        return reply.payload
    }

    func prepareToSend(_ push: Push) async -> Bool {
        precondition(push.topic == topic)

        guard let joinRef = state.access({ $0.joinRef }) else {
            if push.event == .join {
                push.prepareToSend(ref: await socket.makeRef())
                return true
            } else {
                return false
            }
        }

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

    func receiveSocketError() {
        let sendError = state.access { $0.onSocketError() }
        sendError()
    }
}

private extension PhoenixChannel {
    func watchSocketConnection() {
        tasks.storedTask(key: "socketConnection") { [socket, state, weak self] in
            let connectionStates = socket.onConnectionStateChange.allValues
            for await connectionState in connectionStates {
                try Task.checkCancellation()

                switch connectionState {
                case .closed:
                    let onClose = state.access { $0.timedOut() }
                    onClose()

                case .open:
                    self?.scheduleRejoinIfPossible()

                case .waitingToReconnect, .preparingToReconnect,
                     .connecting, .closing:
                    break
                }
            }
        }
    }

    @discardableResult
    func rejoin(timeout: TimeInterval? = nil) async throws -> Payload {
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
        } catch let error as NotReadyToJoinError {
            throw error
        } catch PhoenixError.socketError {
            throw PhoenixError.socketError
        } catch PhoenixError.leavingChannel {
            throw PhoenixError.leavingChannel
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
        tasks.storedNewTask(key: "rejoin") { [weak self] in
            try Task.checkCancellation()
            try await self?.rejoin(timeout: timeout)
        }
    }
}

private struct State: @unchecked Sendable {
    private(set) var connection: Connection
    private var isReadyToJoin: Bool
    private var lastJoinTimeout: TimeInterval?
    private var rejoinAttempts: Int
    private var rejoinDelay: [TimeInterval]

    var joinRef: Ref? {
        switch connection {
        case .unjoined, .errored, .joining, .leaving, .left:
            return nil

        case let .joined(ref, _):
            return ref
        }
    }

    var isErrored: Bool {
        guard case .errored = connection else { return false }
        return true
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
        case errored
        case joined(Ref, reply: Payload)
        case joining(JoinFuture)
        case leaving(LeaveFuture)
        case left
        case unjoined

        var description: String {
            switch self {
            case .errored: return "errored"
            case .joined: return "joined"
            case .joining: return "joining"
            case .leaving: return "leaving"
            case .left: return "left"
            case .unjoined: return "unjoined"
            }
        }
    }

    init(
        connection: Connection = .unjoined,
        rejoinAttempts: Int = 0,
        rejoinDelay: [TimeInterval]
    ) {
        self.connection = connection
        isReadyToJoin = false
        lastJoinTimeout = nil
        self.rejoinAttempts = rejoinAttempts
        self.rejoinDelay = rejoinDelay
    }

    mutating func prepareToJoin() {
        isReadyToJoin = true
    }

    mutating func rejoin(
        topic: Topic,
        payload: Payload,
        socket: PhoenixSocket,
        timeout: TimeInterval?
    ) -> () async throws -> (Ref, Payload) {
        typealias E = PhoenixError

        guard isReadyToJoin else {
            return { throw NotReadyToJoinError() }
        }

        switch connection {
        case .errored, .unjoined:
            let future = JoinFuture()
            connection = .joining(future)

            let attempt = rejoinAttempts
            rejoinAttempts += 1
            let delay = delay(for: attempt)

            // NOTE: When trying to rejoin after an issue,
            // we want to reuse the timeout from the last
            // explicit call to `PhoenixChannel.join(timeout:)`,
            // which is why we keep track of it using
            // `lastJoinTimeout`.
            if let timeout { lastJoinTimeout = timeout }
            let timeout = timeout ?? lastJoinTimeout

            return {
                try await delay()

                // NOTE: Because it's possible for a timeout
                // was never specified for `join(timeout:)`,
                // we fallback to the socket's timeout.
                let timeout = timeout ?? TimeInterval(nanoseconds: socket.timeout)

                let push = Push(
                    topic: topic,
                    event: .join,
                    payload: payload,
                    timeout: Date(timeIntervalSinceNow: timeout)
                )

                let message: Message = try await socket.push(push)
                let (ref, isOk, payload) = try message.refAndReply

                guard isOk else { throw E.joinError }

                return (ref, payload)
            }

        case let .joined(ref, reply):
            return { (ref, reply) }

        case let .joining(future):
            return { try await future.value }

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
        case .unjoined:
            return {}

        case .errored, .joined:
            connection = .errored
            return {}

        case let .joining(future):
            connection = .errored
            return { future.fail(TimeoutError()) }

        case let .leaving(future):
            connection = .left
            return { future.resolve() }

        case .left:
            return {}
        }
    }

    mutating func onSocketError() -> () -> Void {
        switch connection {
        case .unjoined:
            return {}

        case .errored:
            return {}

        case .joined:
            connection = .errored
            return {}

        case let .joining(future):
            connection = .errored
            return { future.fail(PhoenixError.socketError) }

        case let .leaving(future):
            connection = .left
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

private struct NotReadyToJoinError: Error {}
