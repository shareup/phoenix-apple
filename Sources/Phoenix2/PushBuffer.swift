import Foundation
import Synchronized

enum PushResultContinuation: Sendable {
    case onSend(CheckedContinuation<Void, Error>)
    case onReply(CheckedContinuation<Message, Error>)
}

private typealias AwaitingNextContinuation = CheckedContinuation<Push, Never>

final class PushBuffer: AsyncSequence {
    typealias Element = Push

    var isActive: Bool { lock.locked { _isActive } }

    private var _isActive: Bool
    private var awaitingNextContinuation: AwaitingNextContinuation?
    private var inFlightBuffer: [BufferedPush] = []
    private var buffer: [BufferedPush] = []
    private let lock = Lock()

    init(isActive: Bool = false) { _isActive = isActive }

    func makeAsyncIterator() -> PushBuffer.Iterator { Iterator(self) }

    func start() {
        let nextAndCont = lock.locked { () -> (Push, AwaitingNextContinuation)? in
            _isActive = true

            if !buffer.isEmpty, let awaitingNextContinuation = awaitingNextContinuation {
                self.awaitingNextContinuation = nil
                let next = buffer.removeFirst()
                inFlightBuffer.append(next)
                return (next.push, awaitingNextContinuation)
            } else {
                return nil
            }
        }

        guard let (next, cont) = nextAndCont else { return }
        cont.resume(returning: next)
    }

    func stop(_ error: Error) {
        lock.locked { _isActive = false }
        cancelAllInFlight(error)
    }

    func append(_ push: Push) async throws {
        try await withCheckedThrowingContinuation {
            append(push, .onSend($0))
        }
    }

    func appendAndWait(_ push: Push) async throws -> Message {
        try await withCheckedThrowingContinuation {
            append(push, .onReply($0))
        }
    }

    private func append(
        _ push: Push,
        _ continuation: PushResultContinuation
    ) {
        let pushAndCont: (Push, AwaitingNextContinuation)? = lock.locked {
            let bufferedPush = BufferedPush(
                push: push,
                continuation: continuation
            )

            if _isActive, let awaitingNextContinuation = awaitingNextContinuation {
                self.awaitingNextContinuation = nil
                inFlightBuffer.append(bufferedPush)
                return (push, awaitingNextContinuation)
            } else {
                buffer.append(bufferedPush)
                return nil
            }
        }

        guard let (push, cont) = pushAndCont else { return }
        cont.resume(returning: push)
    }

    func didSend(_ push: Push) {
        let bufferedPush: BufferedPush? = lock.locked {
            let index = inFlightBuffer.firstIndex(where: { $0.push == push })
            guard let index = index else { return nil }
            return inFlightBuffer[index].waitForReply
                ? nil
                : inFlightBuffer.remove(at: index)
        }

        guard let bufferedPush = bufferedPush else { return }
        bufferedPush.resume()
    }

    func didReceive(_ message: Message) -> Bool {
        let bufferedPush: BufferedPush? = lock.locked {
            let index = inFlightBuffer.firstIndex(where: message.matches)
            guard let index = index else { return nil }
            return inFlightBuffer.remove(at: index)
        }

        guard let bufferedPush = bufferedPush else { return false }
        bufferedPush.resume(with: message)
        return true
    }

    func cancelAllInFlight(_ error: Error) {
        let inFlight: [BufferedPush] = lock.locked {
            let copy = inFlightBuffer
            inFlightBuffer.removeAll()
            return copy
        }

        inFlight.forEach { $0.resume(with: error) }
    }

    fileprivate func next() async -> Push {
        let next: Push? = lock.locked {
            guard _isActive, !buffer.isEmpty else { return nil }
            let next = buffer.removeFirst()
            inFlightBuffer.append(next)
            return next.push
        }

        if let next = next {
            return next
        } else {
            return await withCheckedContinuation { cont in
                let push: Push? = lock.locked {
                    if _isActive, !buffer.isEmpty {
                        let bufferedPush = buffer.removeFirst()
                        inFlightBuffer.append(bufferedPush)
                        return bufferedPush.push
                    } else {
                        precondition(awaitingNextContinuation == nil)
                        awaitingNextContinuation = cont
                        return nil
                    }
                }

                if let push = push { cont.resume(returning: push) }
            }
        }
    }
}

extension PushBuffer {
    struct Iterator: AsyncIteratorProtocol {
        private let buffer: PushBuffer

        fileprivate init(_ buffer: PushBuffer) { self.buffer = buffer }

        mutating func next() async -> Push? {
            await buffer.next()
        }
    }
}

private struct BufferedPush: Sendable {
    let push: Push
    let continuation: PushResultContinuation

    var waitForReply: Bool {
        switch continuation {
        case .onSend: return false
        case .onReply: return true
        }
    }

    init(push: Push, continuation: PushResultContinuation) {
        self.push = push
        self.continuation = continuation
    }

    func resume() {
        guard case let .onSend(cont) = continuation
        else { preconditionFailure() }
        cont.resume()
    }

    func resume(with message: Message) {
        guard case let .onReply(cont) = continuation
        else { preconditionFailure() }
        cont.resume(returning: message)
    }

    func resume(with error: Error) {
        switch continuation {
        case let .onSend(cont):
            cont.resume(throwing: error)

        case let .onReply(cont):
            cont.resume(throwing: error)
        }
    }
}

private extension Message {
    func matches(_ bufferedPush: BufferedPush) -> Bool {
        topic == bufferedPush.push.topic &&
            joinRef == bufferedPush.push.joinRef &&
            ref == bufferedPush.push.ref
    }
}
