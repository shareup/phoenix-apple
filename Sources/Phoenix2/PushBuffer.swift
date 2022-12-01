import Collections
import Foundation
import Synchronized

final class PushBuffer: AsyncSequence, @unchecked
Sendable {
    typealias Element = Push

    private let state = Locked<State>(.init())

    var isActive: Bool { state.access { $0.isActive } }
    var isIdle: Bool { state.access { $0.isIdle } }
    var isTerminal: Bool { state.access { $0.isTerminal } }

    func makeAsyncIterator() -> PushBuffer.Iterator { PushBuffer.Iterator(self) }

    /// Allows buffered pushes to be iterated over and processed.
    func resume() {
        guard let result = state.access({ $0.resume() })
        else { return }
        result.0.resume(returning: result.1)
    }

    /// Cancels all in-flight pushes while keeping buffered pushes
    /// untouched.
    func pause() {
        let inFlight = state.access { $0.pause() }
        inFlight?.forEach { $0.value.resume(throwing: CancellationError()) }
    }

    /// Appends the push to the internal buffer and waits
    /// for it to be sent before returning.
    func append(_ push: Push) async throws {
        try await withTaskCancellationHandler(
            operation: { () async throws in
                try await withCheckedThrowingContinuation { (cont: SendContinuation) in
                    let result = self.state.access { $0.appendForSend(push, cont) }
                    switch result {
                    case let .cancel(cont):
                        cont.resume(throwing: CancellationError())
                    case let .resume(cont):
                        cont.resume(returning: push)
                    case .wait:
                        break
                    }
                }
            },
            onCancel: { [weak self] in
                let cont = self?.state.access { $0.cancel(push) }
                cont?.resume(throwing: CancellationError())
            }
        )
    }

    /// Appends the push to the internal buffer and waits for
    /// a reply before returning.
    func appendAndWait(_ push: Push) async throws -> Message {
        try await withTaskCancellationHandler(
            operation: { () async throws -> Message in
                try await withCheckedThrowingContinuation { (cont: ReplyContinuation) in
                    let result = self.state.access { $0.appendForReply(push, cont) }
                    switch result {
                    case let .cancel(cont):
                        cont.resume(throwing: CancellationError())
                    case let .resume(cont):
                        cont.resume(returning: push)
                    case .wait:
                        break
                    }
                }
            },
            onCancel: { [weak self] in
                let cont = self?.state.access { $0.cancel(push) }
                cont?.resume(throwing: CancellationError())
            }
        )
    }

    /// Notifies `PushBuffer` that the push has been sent. The
    /// corresponding call to `append()` will be allowed to
    /// return.
    func didSend(_ push: Push) {
        let cont = state.access { $0.removeSendContinuation(for: push) }
        cont?.resume()
    }

    /// Notifies `PushBuffer` that the push has received a reply. The
    /// corresponding call to `appendAndWait()` will be allowed to
    /// return.
    func didReceive(_ message: Message) -> Bool {
        let cont = state.access { $0.removeReplyContinuation(for: message) }
        guard let cont else { return false }
        cont.resume(returning: message)
        return true
    }

    /// Cancels all in-flight and buffered pushes and invalidates the
    /// buffer. Any subsequent calls to `append()`, `appendAndWait()`,
    /// or `next()` with return with a `CancellationError`. Calls
    /// to `didSend()` or `didReceive()` will be no-ops.
    func cancelAllAndInvalidate() {
        let result = state.access { $0.finish() }
        result.1?.forEach { $0.value.resume(throwing: CancellationError()) }
        result.0?.resume(throwing: CancellationError())
    }

    fileprivate func next() async throws -> Push {
        try await withTaskCancellationHandler(
            operation: { () async throws -> Push in
                try await withCheckedThrowingContinuation { (cont: AwaitingPushContinuation) in
                    do {
                        let push = try state.access { try $0.next(cont) }
                        guard let push else { return }
                        cont.resume(returning: push)
                    } catch {
                        cont.resume(throwing: error)
                    }
                }
            },
            onCancel: { [weak self] in
                let result = self?.state.access
                    { (state: inout State) -> (AwaitingPushContinuation?, Pushes?) in
                        let cont = state.awaitingPushContinuation
                        state.awaitingPushContinuation = nil
                        let pushes = state.pause()
                        return (cont: cont, pushes: pushes)
                    }

                guard let result else { return }
                result.1?.forEach { $0.value.resume(throwing: CancellationError()) }
                result.0?.resume(throwing: CancellationError())
            }
        )
    }
}

extension PushBuffer {
    struct Iterator: AsyncIteratorProtocol {
        private let buffer: PushBuffer

        fileprivate init(_ buffer: PushBuffer) { self.buffer = buffer }

        mutating func next() async throws -> Push? {
            try await buffer.next()
        }
    }
}

private enum Continuation {
    case reply(ReplyContinuation)
    case send(SendContinuation)

    func resume(throwing error: Error) {
        switch self {
        case let .reply(cont): cont.resume(throwing: error)
        case let .send(cont): cont.resume(throwing: error)
        }
    }

    init(_ cont: ReplyContinuation) { self = .reply(cont) }
    init(_ cont: SendContinuation) { self = .send(cont) }
}

/// A continuation stored in `State` while its waiting for new
/// pushes to be appended.
private typealias AwaitingPushContinuation = CheckedContinuation<Push, Error>

/// A continuation resolved when a Push receives a reply.
private typealias ReplyContinuation = CheckedContinuation<Message, Error>

/// A continuation resolved when a Push is sent. Replies are ignored.
private typealias SendContinuation = CheckedContinuation<Void, Error>

private typealias Pushes = OrderedDictionary<Push, Continuation>

private enum AppendResult {
    case cancel(Continuation)
    case resume(AwaitingPushContinuation)
    case wait
}

private extension PushBuffer {
    struct State {
        var awaitingPushContinuation: AwaitingPushContinuation?

        private(set) var queue = Queue()

        /// Holds cancelled pushes that haven't yet been added
        /// to queue. This can happen when the cancellation block
        /// is called before the operation block of
        /// `withTaskCancellationHandler()`
        private var cancelled = Set<Push>()

        var isActive: Bool {
            guard case .active = queue else { return false }
            return true
        }

        var isIdle: Bool {
            guard case .idle = queue else { return false }
            return true
        }

        var isTerminal: Bool {
            guard case .terminal = queue else { return false }
            return true
        }

        mutating func next(_ continuation: AwaitingPushContinuation) throws -> Push? {
            guard !queue.isTerminal else { throw CancellationError() }
            if let next = queue.next() {
                return next
            } else {
                precondition(awaitingPushContinuation == nil)
                awaitingPushContinuation = continuation
                return nil
            }
        }

        mutating func pause() -> Pushes? { queue.pause() }

        mutating func cancel(_ push: Push) -> Continuation? {
            guard let cont = queue.cancel(push) else {
                cancelled.insert(push)
                return nil
            }
            return cont
        }

        mutating func resume() -> (AwaitingPushContinuation, Push)? {
            if let awaitingPushContinuation {
                guard let push = queue.resumeAndPopFirst()
                else { return nil }
                self.awaitingPushContinuation = nil
                return (awaitingPushContinuation, push)
            } else {
                queue.resume()
                return nil
            }
        }

        mutating func finish() -> (AwaitingPushContinuation?, Pushes?) {
            let pushes = queue.finish()
            let cont = awaitingPushContinuation
            awaitingPushContinuation = nil
            return (cont, pushes)
        }

        mutating func appendForReply(
            _ push: Push,
            _ continuation: ReplyContinuation
        ) -> AppendResult {
            guard !cancelled.contains(push) else {
                cancelled.remove(push)
                return .cancel(.reply(continuation))
            }

            if let awaitingPushContinuation,
               queue.addToInFlightForReply(push, continuation)
            {
                self.awaitingPushContinuation = nil
                return .resume(awaitingPushContinuation)
            } else {
                if let cont = queue.appendForReply(push, continuation) {
                    return .cancel(cont)
                } else {
                    return .wait
                }
            }
        }

        mutating func appendForSend(
            _ push: Push,
            _ continuation: SendContinuation
        ) -> AppendResult {
            guard !cancelled.contains(push) else {
                cancelled.remove(push)
                return .cancel(.send(continuation))
            }

            if let awaitingPushContinuation,
               queue.addToInFlightForSend(push, continuation)
            {
                self.awaitingPushContinuation = nil
                return .resume(awaitingPushContinuation)
            } else {
                if let cont = queue.appendForSend(push, continuation) {
                    return .cancel(cont)
                } else {
                    return .wait
                }
            }
        }

        mutating func removeReplyContinuation(for message: Message) -> ReplyContinuation? {
            queue.removeReplyContinuation(for: message)
        }

        mutating func removeSendContinuation(for push: Push) -> SendContinuation? {
            queue.removeSendContinuation(for: push)
        }
    }
}

private enum Queue {
    case active(inFlight: Pushes, buffer: Pushes)
    case idle(buffer: Pushes)
    case terminal

    var isTerminal: Bool {
        guard case .terminal = self else { return false }
        return true
    }

    init() { self = .idle(buffer: .init()) }

    mutating func resume() {
        switch self {
        case .active:
            break

        case let .idle(buffer):
            self = .active(inFlight: .init(), buffer: buffer)

        case .terminal:
            break
        }
    }

    mutating func resumeAndPopFirst() -> Push? {
        switch self {
        case .active, .terminal:
            return nil

        case let .idle(buffer) where buffer.isEmpty:
            self = .active(inFlight: .init(), buffer: buffer)
            return nil

        case var .idle(buffer):
            let first = buffer.removeFirst()
            self = .active(
                inFlight: .init(dictionaryLiteral: first),
                buffer: buffer
            )
            return first.key
        }
    }

    mutating func pause() -> Pushes? {
        switch self {
        case let .active(inFlight, buffer):
            self = .idle(buffer: buffer)
            return inFlight

        case .idle, .terminal:
            return nil
        }
    }

    mutating func finish() -> Pushes? {
        switch self {
        case let .active(inFlight, buffer):
            self = .terminal
            return inFlight.merging(buffer) { _, _ in preconditionFailure() }

        case let .idle(buffer):
            self = .terminal
            return buffer

        case .terminal:
            return nil
        }
    }

    mutating func cancel(_ push: Push) -> Continuation? {
        switch self {
        case var .active(inFlight, buffer):
            if let cont = inFlight.removeValue(forKey: push) {
                self = .active(inFlight: inFlight, buffer: buffer)
                return .init(cont)
            } else if let cont = buffer.removeValue(forKey: push) {
                self = .active(inFlight: inFlight, buffer: buffer)
                return .init(cont)
            } else {
                return nil
            }

        case var .idle(buffer):
            if let cont = buffer.removeValue(forKey: push) {
                self = .idle(buffer: buffer)
                return .init(cont)
            } else {
                return nil
            }

        case .terminal:
            return nil
        }
    }

    /// Adds the push to in-flight pushes if active. If idle, this
    /// method does nothing. Calling this method when terminal is
    /// user error and undefined. Returns `true` if the push was
    /// added to in-flight pushes, otherwise `false`.
    mutating func addToInFlightForReply(
        _ push: Push,
        _ continuation: ReplyContinuation
    ) -> Bool {
        addToInFlight(push, .reply(continuation))
    }

    /// Adds the push to in-flight pushes if active. If idle, this
    /// method does nothing. Calling this method when terminal is
    /// user error and undefined. Returns `true` if the push was
    /// added to in-flight pushes, otherwise `false`.
    mutating func addToInFlightForSend(
        _ push: Push,
        _ continuation: SendContinuation
    ) -> Bool {
        addToInFlight(push, .send(continuation))
    }

    private mutating func addToInFlight(
        _ push: Push,
        _ continuation: Continuation
    ) -> Bool {
        guard case .active(var inFlight, let buffer) = self
        else { return false }

        precondition(buffer.isEmpty)

        inFlight[push] = continuation
        self = .active(inFlight: inFlight, buffer: buffer)
        return true
    }

    /// Adds the Push and continuation to the buffer. If the buffer
    /// has finished, this method directly returns the continuation
    /// to the caller so that it may be cancelled.
    mutating func appendForReply(
        _ push: Push,
        _ continuation: ReplyContinuation
    ) -> Continuation? {
        append(push, .init(continuation))
    }

    /// Adds the Push and continuation to the buffer. If the buffer
    /// has finished, this method directly returns the continuation
    /// to the caller so that it may be cancelled.
    mutating func appendForSend(
        _ push: Push,
        _ continuation: SendContinuation
    ) -> Continuation? {
        append(push, .init(continuation))
    }

    private mutating func append(
        _ push: Push,
        _ continuation: Continuation
    ) -> Continuation? {
        switch self {
        case .active(let inFlight, var buffer):
            buffer[push] = continuation
            self = .active(inFlight: inFlight, buffer: buffer)
            return nil

        case var .idle(buffer):
            buffer[push] = continuation
            self = .idle(buffer: buffer)
            return nil

        case .terminal:
            return continuation
        }
    }

    /// Removes the `ReplyContinuation` from in-flight pushes, if it
    /// exists. Trying to remove a `SendContinuation` is user error
    /// and undefined behavior. Also, trying to remove a continuation
    /// from the buffer is user error and undefined behavior.
    mutating func removeReplyContinuation(for message: Message) -> ReplyContinuation? {
        switch self {
        case .active(var inFlight, let buffer):
            precondition(buffer.findPush(matching: message.ref) == nil)
            guard let cont = inFlight.remove(matching: message)
            else { return nil }
            self = .active(inFlight: inFlight, buffer: buffer)
            return cont

        case let .idle(buffer):
            precondition(buffer.findPush(matching: message.ref) == nil)
            return nil

        case .terminal:
            return nil
        }
    }

    /// Removes the `SendContinuation` from in-flight pushes, if it
    /// exists. If the push's continuation is a `ReplyContinuation`,
    /// this method returns `nil`. Trying to remove a continuation
    /// from the buffer is user error and undefined behavior.
    mutating func removeSendContinuation(for push: Push) -> SendContinuation? {
        switch self {
        case .active(var inFlight, let buffer):
            precondition(buffer[push] == nil)
            guard case let .send(cont) = inFlight[push] else { return nil }
            inFlight.removeValue(forKey: push)
            self = .active(inFlight: inFlight, buffer: buffer)
            return cont

        case let .idle(buffer):
            precondition(buffer[push] == nil)
            return nil

        case .terminal:
            return nil
        }
    }

    /// Returns the first buffered `Push`, if active. If idle, returns
    /// nil. Calling this method when terminal is a user error and
    /// undefined behavior.
    mutating func next() -> Push? {
        switch self {
        case var .active(inFlight, buffer):
            guard !buffer.isEmpty else { return nil }
            let next = buffer.removeFirst()
            inFlight[next.key] = next.value
            self = .active(inFlight: inFlight, buffer: buffer)
            return next.key

        case .idle:
            return nil

        case .terminal:
            preconditionFailure()
        }
    }
}

private extension Pushes {
    func findPush(matching ref: Ref?) -> Push? {
        guard let ref else { return nil }
        let match = first(where: { (key: Push, _: Continuation) -> Bool in
            key.ref == ref
        })
        guard let match else { return nil }
        return match.key
    }

    mutating func remove(matching message: Message) -> ReplyContinuation? {
        guard let push = findPush(matching: message.ref),
              case let .reply(cont) = self[push]
        else { return nil }

        removeValue(forKey: push)

        return cont
    }
}
