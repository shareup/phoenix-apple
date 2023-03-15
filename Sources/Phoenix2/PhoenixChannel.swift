import AsyncExtensions
import Combine
import Foundation
import os.log
import Synchronized

private typealias JoinFuture = AsyncExtensions.Future<(Ref, Payload)>
private typealias LeaveFuture = AsyncExtensions.Future<Void>

final class PhoenixChannel: Sendable {
    let topic: Topic
    let joinPayload: Payload

    private let socket: PhoenixSocket
    private let state = Locked(State())

    init(
        topic: Topic,
        joinPayload: Payload = [:],
        socket: PhoenixSocket
    ) {
        self.topic = topic
        self.joinPayload = joinPayload
        self.socket = socket

        state.access { state in
            state.subscribeToStateChange(
                socket: socket,
                block: onSocketConnectionChange
            )
        }
    }

    @discardableResult
    func join(timeout: TimeInterval? = nil) async throws -> Payload {
        let join = try state.access { state in
            try state.join(
                topic: topic,
                payload: joinPayload,
                socket: socket,
                timeout: timeout ?? TimeInterval(nanoseconds: socket.timeout)
            )
        }

        do {
            let (ref, reply) = try await join()
            let future = state.access { $0.didJoin(ref: ref, reply: reply) }
            future?.resolve((ref, reply))
            return reply
        } catch {
            state.access { $0.didFailJoin() }?.fail(error)
            throw error
        }
    }

    func leave(timeout: TimeInterval? = nil) async throws {
        let leave = state.access { state in
            state.leave(
                topic: topic,
                socket: socket,
                timeout: timeout ?? TimeInterval(nanoseconds: socket.timeout)
            )
        }

        do {
            try await leave()
            // didLeave
        } catch {
            // force leave
        }
    }

    func prepareToSend(_ push: Push) async -> Bool {
        precondition(push.topic == topic)

        guard let joinRef = state.access({ $0.joinRef })
        else { return false }

        push.prepareToSend(ref: await socket.makeRef(), joinRef: joinRef)
        return true
    }

    func isMember(_ message: Message) -> Bool {
        guard topic == message.topic else { return false }

        return state.access { state in
            switch state.connection {
            case let .joined(joinRef, _):
                if message.joinRef == joinRef {
                    return true
                } else {
                    os_log(
                        "channel outdated message: joinRef=%d message=%d",
                        log: .phoenix,
                        type: .debug,
                        Int(joinRef.rawValue),
                        Int(message.joinRef?.rawValue ?? 0)
                    )
                    return false
                }

            case .closed, .errored, .joining, .leaving:
                return true
            }
        }
    }
}

private extension PhoenixChannel {
    var onSocketConnectionChange: (PhoenixSocket.ConnectionState) -> Void {
        { [weak self] (connectionState: PhoenixSocket.ConnectionState) in
            guard let self else { return }

            switch connectionState {
            case .closed:
                self.state.access { $0.close() }

            case .open:
                // TODO: rejoin
                break

            case .waitingToReconnect, .preparingToReconnect,
                 .connecting, .closing:
                break
            }
        }
    }
}

private struct State: @unchecked Sendable {
    var didJoin: Bool
    var connection: Connection
    var socketStateChangeSubscription: AnyCancellable?

    var joinRef: Ref? {
        switch connection {
        case .closed, .errored, .joining, .leaving:
            return nil

        case let .joined(ref, _):
            return ref
        }
    }

    enum Connection: CustomStringConvertible {
        case closed
        case errored
        case joined(Ref, reply: Payload)
        case joining(JoinFuture)
        case leaving(LeaveFuture)

        var description: String {
            switch self {
            case .closed: "closed"
            case .errored: "errored"
            case .joined: "joined"
            case .joining: "joining"
            case .leaving: "leaving"
            }
        }
    }

    init(
        didJoin: Bool = false,
        connection: Connection = .closed,
        socketStateChangeSubscription: AnyCancellable? = nil
    ) {
        self.didJoin = didJoin
        self.connection = connection
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

    mutating func join(
        topic: Topic,
        payload: Payload,
        socket: PhoenixSocket,
        timeout: TimeInterval
    ) throws -> () async throws -> (Ref, Payload) {
        guard !didJoin else { throw PhoenixError.alreadyJoinedChannel }
        didJoin = true

        return rejoin(
            topic: topic,
            payload: payload,
            socket: socket,
            timeout: timeout
        )
    }

    mutating func rejoin(
        topic: Topic,
        payload: Payload,
        socket: PhoenixSocket,
        timeout: TimeInterval
    ) -> () async throws -> (Ref, Payload) {
        typealias E = PhoenixError

        switch connection {
        case .closed, .errored:
            let future = JoinFuture()
            connection = .joining(future)

            return {
                let push = Push(
                    topic: topic,
                    event: .join,
                    payload: payload,
                    timeout: Date(timeIntervalSinceNow: timeout)
                )

                let message: Message = try await socket.push(push)
                let (isOk, ref, payload) = try message.reply

                guard isOk else {
                    throw E.joinError(message.error ?? "unknown")
                }

                return (ref, payload)
            }

        case let .joined(ref, reply):
            return { (ref, reply) }

        case let .joining(future):
            return { return try await future.value }

        case .leaving:
            return { throw PhoenixError.leavingChannel }
        }
    }

    mutating func didJoin(ref: Ref, reply: Payload) -> JoinFuture? {
        switch connection {
        case .closed, .errored, .joined, .leaving:
            assertionFailure(
                "invalid state for didJoin: \(connection.description)"
            )
            return nil

        case let .joining(future):
            connection = .joined(ref, reply: reply)
            return future
        }
    }

    mutating func didFailJoin() -> JoinFuture? {
        switch connection {
        case .closed, .errored, .joined, .leaving:
            assertionFailure(
                "invalid state for didJoin: \(connection.description)"
            )
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
        case .closed, .errored:
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
        case .closed, .errored, .joined, .joining:
            return nil

        case let .leaving(future):
            connection = .closed
            return future
        }
    }

    mutating func didFailLeave(error: Error) -> LeaveFuture? {
        switch connection {
        case .closed, .errored, .joined, .joining:
            return nil

        case let .leaving(future):
            if error is TimeoutError {}
            connection = .closed
            return future
        }
    }

    mutating func close() {
        switch connection {
        case .closed, .errored:
            break
        case .joined, .joining, .leaving:
            connection = .closed
        }
    }
}
