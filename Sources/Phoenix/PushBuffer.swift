import AsyncExtensions
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

    deinit {
        self.cancelAllAndInvalidate()
    }

    func makeAsyncIterator() -> PushBuffer.Iterator { PushBuffer.Iterator(self) }

    /// Allows buffered pushes to be iterated over and processed.
    func resume() {
        guard let result = state.access({ $0.resume() })
        else { return }
        result.0.resume(returning: result.1)
    }

    /// Cancels all in-flight pushes with the specified error or
    /// `CancellationError`. Buffered pushes are untouched.
    func pause(error: Error? = nil) {
        let inFlight = state.access { $0.pause() }
        let error = error ?? CancellationError()
        inFlight?.forEach { $0.value.resume(throwing: error) }
    }

    /// Appends the push to the internal buffer and waits
    /// for it to be sent before returning.
    func append(_ push: Push) async throws {
        setTimeout(push.timeout)

        try await withTaskCancellationHandler(
            operation: {
                try await withUnsafeThrowingContinuation { (cont: SendContinuation) in
                    let result = self.state.access { $0.appendForSend(push, cont) }
                    switch result {
                    case let .cancel(cont, error):
                        cont.resume(throwing: error)
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
        setTimeout(push.timeout)

        return try await withTaskCancellationHandler(
            operation: {
                try await withUnsafeThrowingContinuation { (cont: ReplyContinuation) in
                    let result = self.state.access { $0.appendForReply(push, cont) }
                    switch result {
                    case let .cancel(cont, error):
                        cont.resume(throwing: error)
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

    /// Notifies `PushBuffer` the push has been sent. The
    /// corresponding call to `append()` will be allowed to
    /// return.
    func didSend(_ push: Push) {
        let cont = state.access { $0.removeSendContinuation(for: push) }
        cont?.resume()
    }

    /// Notifies `PushBuffer` the push has received a reply. The
    /// corresponding call to `appendAndWait()` will be allowed to
    /// return.
    func didReceive(_ message: Message) -> Bool {
        let cont = state.access { $0.removeReplyContinuation(for: message) }
        guard let cont else { return false }
        cont.resume(returning: message)
        return true
    }

    /// Notifies `PushBuffer` the push has failed. The corresponding
    /// call to `append()` or `appendAndWait()` will throw the
    /// specified error.
    @discardableResult
    func didFail(_ push: Push, error: Error) -> Bool {
        let cont = state.access { $0.fail(push, error: error) }
        guard let cont else { return false }
        cont.resume(throwing: error)
        return true
    }

    /// Moves the in-flight `Push` back into buffer. Returns `true` if
    /// the `Push` was put back into the buffer or if it was already in
    /// the buffer, otherwise `false`.
    @discardableResult
    func putBack(_ push: Push) -> Bool {
        state.access { $0.putBack(push) }
    }

    /// Cancels all in-flight and buffered pushes and invalidates the
    /// buffer with the specified error or `CancellationError`. Any
    /// subsequent calls to `append()`, `appendAndWait()`, or `next()`
    /// with return with a `CancellationError`. Calls to `didSend()`,
    /// `didReceive()`, or `putBack()` will be no-ops.
    func cancelAllAndInvalidate(error: Error? = nil) {
        let error = error ?? CancellationError()
        let result = state.access { $0.finish(error: error) }
        result.1?.forEach { $0.value.resume(throwing: error) }
        result.0?.resume(throwing: error)
    }

    fileprivate func next() async throws -> Push {
        // NOTE: This is `Sendable` because we only access it
        // inside of the state's locked access blocks.
        class Cancellation: @unchecked Sendable {
            var isCancelled = false
        }

        let cancellation = Cancellation()

        return try await withTaskCancellationHandler(
            operation: { () async throws -> Push in
                try await withUnsafeThrowingContinuation { (cont: AwaitingPushContinuation) in
                    do {
                        let push: Push? = try state.access { state in
                            if cancellation.isCancelled {
                                throw CancellationError()
                            } else {
                                return try state.next(cont)
                            }
                        }

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
                        cancellation.isCancelled = true
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

    private func setTimeout(_ date: Date) {
        // Maximum of one hour timeout because `.distantFuture` timeouts
        // cause `Task.sleep(nanoseconds:)` to return immediately, for
        // some reason.
        let timeoutNs = Swift.min(
            date.timeIntervalSinceNow.nanoseconds,
            NSEC_PER_SEC * 60 * 60
        )

        state.access { state in
            state.setTimeout(date) {
                Task.detached { [weak self] in
                    try await Task.sleep(nanoseconds: timeoutNs)
                    self?.timeout()
                }
            }
        }
    }

    private func timeout() {
        let result = state.access { $0.timeout(at: Date()) }
        result.forEach { $0.resume(throwing: TimeoutError()) }

        if let nextTimeout = state.access({ $0.nextTimeout() }) {
            setTimeout(nextTimeout)
        }
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
private typealias AwaitingPushContinuation = UnsafeContinuation<Push, Error>

/// A continuation resolved when a Push receives a reply.
private typealias ReplyContinuation = UnsafeContinuation<Message, Error>

/// A continuation resolved when a Push is sent. Replies are ignored.
private typealias SendContinuation = UnsafeContinuation<Void, Error>

private typealias Pushes = OrderedDictionary<Push, Continuation>
private typealias BufferedPushes = OrderedDictionary<Topic, Pushes>

private enum AppendResult {
    case cancel(Continuation, Error)
    case resume(AwaitingPushContinuation)
    case wait
}

private extension PushBuffer {
    struct State {
        var awaitingPushContinuation: AwaitingPushContinuation?

        private(set) var queue = Queue()

        /// Holds pushes that have received an error before they
        /// were added to the queue. For example, this could happen
        /// when the cancellation block is called before the operation
        /// block of `withTaskCancellationHandler()`.
        private var errored = [Push: Error]()

        private var timeout: Timeout?

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
            if case let .terminal(error) = queue {
                throw error
            }

            if let next = queue.next() {
                return next
            } else {
                precondition(awaitingPushContinuation == nil)
                awaitingPushContinuation = continuation
                return nil
            }
        }

        mutating func putBack(_ push: Push) -> Bool { queue.putBack(push) }

        mutating func pause() -> Pushes? { queue.pause() }

        mutating func cancel(_ push: Push) -> Continuation? {
            fail(push, error: CancellationError())
        }

        mutating func timeout(at date: Date) -> [Continuation] {
            timeout = nil
            let timedOut = queue.timeout(at: date)
            timedOut.keys.forEach { errored[$0] = TimeoutError() }
            return Array(timedOut.values)
        }

        mutating func fail(_ push: Push, error: Error) -> Continuation? {
            guard let cont = queue.fail(push) else {
                errored[push] = error
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

        mutating func finish(error: Error) -> (AwaitingPushContinuation?, Pushes?) {
            let pushes = queue.finish(error: error)
            let cont = awaitingPushContinuation
            awaitingPushContinuation = nil
            timeout?.cancel()
            return (cont, pushes)
        }

        mutating func setTimeout(_ date: Date, makeTask: () -> Task<Void, Error>) {
            if let timeout {
                guard date < timeout.date else { return }
                self.timeout = Timeout(date: date, task: makeTask())
            } else {
                timeout = Timeout(date: date, task: makeTask())
            }
        }

        func nextTimeout() -> Date? { queue.nextTimeout() }

        mutating func appendForReply(
            _ push: Push,
            _ continuation: ReplyContinuation
        ) -> AppendResult {
            if let error = errored.removeValue(forKey: push) {
                return .cancel(.reply(continuation), error)
            }

            if let awaitingPushContinuation,
               queue.addToInFlightForReply(push, continuation)
            {
                self.awaitingPushContinuation = nil
                return .resume(awaitingPushContinuation)
            } else {
                if let contAndError = queue.appendForReply(push, continuation) {
                    return .cancel(contAndError.0, contAndError.1)
                } else {
                    return .wait
                }
            }
        }

        mutating func appendForSend(
            _ push: Push,
            _ continuation: SendContinuation
        ) -> AppendResult {
            if let error = errored.removeValue(forKey: push) {
                return .cancel(.send(continuation), error)
            }

            if let awaitingPushContinuation,
               queue.addToInFlightForSend(push, continuation)
            {
                self.awaitingPushContinuation = nil
                return .resume(awaitingPushContinuation)
            } else {
                if let contAndError = queue.appendForSend(push, continuation) {
                    return .cancel(contAndError.0, contAndError.1)
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

private struct Timeout {
    let date: Date
    let task: Task<Void, Error>

    func cancel() {
        task.cancel()
    }
}

private enum Queue {
    case active(inFlight: Pushes, buffer: BufferedPushes)
    case idle(buffer: BufferedPushes)
    case terminal(Error)

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
            var (topic, pushes) = buffer.removeFirst()
            let first = pushes.removeFirst()
            if !pushes.isEmpty { buffer[topic] = pushes }
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

    mutating func finish(error: Error) -> Pushes? {
        switch self {
        case let .active(inFlight, buffer):
            self = .terminal(error)
            return inFlight.merging(buffer)

        case let .idle(buffer):
            self = .terminal(error)
            return buffer.pushes

        case .terminal:
            return nil
        }
    }

    mutating func fail(_ push: Push) -> Continuation? {
        switch self {
        case var .active(inFlight, buffer):
            if let cont = inFlight.removeValue(forKey: push) {
                self = .active(inFlight: inFlight, buffer: buffer)
                return cont
            } else if var pushes = buffer.removeValue(forKey: push.topic) {
                let cont: Continuation? = pushes.removeValue(forKey: push)
                if !pushes.isEmpty { buffer[push.topic] = pushes }
                self = .active(inFlight: inFlight, buffer: buffer)
                return cont
            } else {
                return nil
            }

        case var .idle(buffer):
            if var pushes = buffer.removeValue(forKey: push.topic) {
                let cont: Continuation? = pushes.removeValue(forKey: push)
                if !pushes.isEmpty { buffer[push.topic] = pushes }
                self = .idle(buffer: buffer)
                return cont
            } else {
                return nil
            }

        case .terminal:
            return nil
        }
    }

    func nextTimeout() -> Date? {
        func nextTimeout(in pushes: Pushes) -> Date? {
            pushes.reduce(into: nil as Date?) { acc, elem in
                let push: Push = elem.key

                guard var acc else {
                    acc = push.timeout
                    return
                }

                acc = acc.compare(push.timeout) == .orderedAscending
                    ? acc
                    : push.timeout
            }
        }

        switch self {
        case let .active(inFlight, buffer):
            return nextTimeout(in: inFlight.merging(buffer))

        case let .idle(buffer):
            return nextTimeout(in: buffer.pushes)

        case .terminal:
            return nil
        }
    }

    mutating func timeout(at date: Date) -> Pushes {
        func isTimedOut(_ push: Push) -> Bool {
            push.timeout <= date
        }

        func isTimedOut(_ element: (Push, Continuation)) -> Bool {
            isTimedOut(element.0)
        }

        switch self {
        case var .active(inFlight, buffer):
            let timedOutInFlight = inFlight.filter(isTimedOut)
            timedOutInFlight.forEach { inFlight.removeValue(forKey: $0.key) }

            let timedOutBuffered = buffer.removePushes(where: isTimedOut)

            self = .active(inFlight: inFlight, buffer: buffer)
            return timedOutInFlight.merging(timedOutBuffered)

        case var .idle(buffer):
            let timedOut = buffer.removePushes(where: isTimedOut)
            self = .idle(buffer: buffer)
            return timedOut

        case .terminal:
            return [:]
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

        inFlight.append(continuation, forKey: push)
        self = .active(inFlight: inFlight, buffer: buffer)
        return true
    }

    /// Adds the Push and continuation to the buffer. If the buffer
    /// has finished, this method directly returns the continuation
    /// to the caller so that it may be cancelled.
    mutating func appendForReply(
        _ push: Push,
        _ continuation: ReplyContinuation
    ) -> (Continuation, Error)? {
        append(push, .init(continuation))
    }

    /// Adds the Push and continuation to the buffer. If the buffer
    /// has finished, this method directly returns the continuation
    /// to the caller so that it may be cancelled.
    mutating func appendForSend(
        _ push: Push,
        _ continuation: SendContinuation
    ) -> (Continuation, Error)? {
        append(push, .init(continuation))
    }

    private mutating func append(
        _ push: Push,
        _ continuation: Continuation
    ) -> (Continuation, Error)? {
        switch self {
        case .active(let inFlight, var buffer):
            buffer.updateValue(
                forKey: push.topic,
                default: Pushes(),
                with: { $0.append(continuation, forKey: push) }
            )
            self = .active(inFlight: inFlight, buffer: buffer)
            return nil

        case var .idle(buffer):
            buffer.updateValue(
                forKey: push.topic,
                default: Pushes(),
                with: { $0.append(continuation, forKey: push) }
            )
            self = .idle(buffer: buffer)
            return nil

        case let .terminal(error):
            return (continuation, error)
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
            precondition(!buffer.contains(push))
            guard case let .send(cont) = inFlight[push] else { return nil }
            inFlight.removeValue(forKey: push)
            self = .active(inFlight: inFlight, buffer: buffer)
            return cont

        case let .idle(buffer):
            precondition(!buffer.contains(push))
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
            var (topic, pushes) = buffer.removeFirst()
            let next = pushes.removeFirst()
            inFlight[next.key] = next.value
            if !pushes.isEmpty { buffer[topic] = pushes }
            self = .active(inFlight: inFlight, buffer: buffer)
            return next.key

        case .idle:
            return nil

        case .terminal:
            preconditionFailure()
        }
    }

    mutating func putBack(_ push: Push) -> Bool {
        switch self {
        case var .active(inFlight, buffer):
            guard let cont = inFlight.removeValue(forKey: push)
            else { return buffer.contains(push) }
            buffer.updateValue(
                forKey: push.topic,
                default: Pushes(),
                with: { $0.insertAtStart(cont, forKey: push) }
            )
            self = .active(inFlight: inFlight, buffer: buffer)
            return true

        case let .idle(buffer):
            return buffer.contains(push)

        case .terminal:
            return false
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

    mutating func merge(_ other: Pushes) {
        merge(other, uniquingKeysWith: { _, _ in preconditionFailure() })
    }

    func merging(_ other: Pushes) -> Pushes {
        merging(other, uniquingKeysWith: { _, _ in preconditionFailure() })
    }

    func merging(_ other: BufferedPushes) -> Pushes {
        merging(other.pushes)
    }

    /// Appends the key-value pair at the end of the `OrderedDictionary`
    /// unless `key.event` is equal to `.join`, in which case it inserts
    /// the key-value pair after the last join push.
    mutating func append(_ value: Continuation, forKey key: Push) {
        if key.event == .join {
            var insertAtIndex = 0
            for (push, _) in self {
                guard push.event == .join else { break }
                insertAtIndex += 1
            }
            let (originalMember, _) = updateValue(
                value,
                forKey: key,
                insertingAt: insertAtIndex
            )
            precondition(originalMember == nil)
        } else {
            self[key] = value
        }
    }

    mutating func insertAtStart(_ value: Continuation, forKey key: Push) {
        var insertAtIndex = 0

        // If the push isn't a join, insert it after the rest of the joins.
        // If the push is a join, insert it at the beginning.
        if key.event != .join {
            for (push, _) in self {
                guard push.event == .join else { break }
                insertAtIndex += 1
            }
        }

        let (originalMember, _) = updateValue(
            value,
            forKey: key,
            insertingAt: insertAtIndex
        )

        precondition(originalMember == nil)
    }
}

private extension BufferedPushes {
    var pushes: Pushes {
        reduce(into: Pushes()) { acc, value in
            let (_, pushes) = value
            acc.merge(pushes)
        }
    }

    func contains(_ push: Push) -> Bool {
        self[push.topic]?[push] != nil
    }

    func findPush(matching ref: Ref?) -> Push? {
        guard let ref else { return nil }
        for (_, pushes) in self {
            if let push = pushes.findPush(matching: ref) {
                return push
            }
        }
        return nil
    }

    mutating func removePushes(where predicate: (Push) -> Bool) -> Pushes {
        var removed = Pushes()
        self = reduce(into: BufferedPushes()) { acc, value in
            var (topic, pushes) = value
            let filteredOut = pushes.filter { predicate($0.0) }
            filteredOut.forEach { pushes.removeValue(forKey: $0.key) }
            if !pushes.isEmpty { acc[topic] = pushes }
            removed.merge(filteredOut)
        }
        return removed
    }
}
