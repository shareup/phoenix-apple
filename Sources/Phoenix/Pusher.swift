import Foundation
import Synchronized

class Pusher: Synchronized {
    static let maximumRetries = 2

    typealias Callback = ([(Push, OutgoingMessage)]) -> Void

    private var pending: [(retries: Int, ref: Ref, push: Channel.Push)] = []
    private var tracked: [(Push, OutgoingMessage)] = []
    private var willRetryLater: Bool = false
    private var willReceiveBatchSoon: Bool = false
    private var receiveBatchCallback: Callback? = nil

    var generator = Ref.Generator()

    enum Push {
        case channel(Channel.Push)
        case socket(Socket.Push)

        init(_ push: Channel.Push) {
            self = .channel(push)
        }

        init(_ push: Socket.Push) {
            self = .socket(push)
        }
    }

    enum Errors: Error {
        case multipleReceiveBatchCallbacks
    }

    func receiveBatch(callback: @escaping Callback) throws {
        try sync {
            guard receiveBatchCallback == nil else {
                throw Errors.multipleReceiveBatchCallbacks
            }

            self.receiveBatchCallback = callback

            if tracked.count > 0 {
                receiveCurrentBatchSoon()
            }
        }
    }

    private func receiveCurrentBatchSoon() {
        sync {
            guard !willReceiveBatchSoon else { return }
            willReceiveBatchSoon = true
        }

        let deadline = DispatchTime.now().advanced(by: .milliseconds(100))

        DispatchQueue.global().asyncAfter(deadline: deadline) {
            self.receiveCurrentBatch()
        }
    }

    private func receiveCurrentBatch() {
        sync {
            guard tracked.count > 0 else { return }
            guard let cb = receiveBatchCallback else { return }

            self.receiveBatchCallback = nil // clear out for next batch

            let _messages = tracked
            tracked.removeAll()

            cb(_messages)
        }
    }

    func send(_ push: Channel.Push) -> Ref {
        sync {
            let ref = generator.advance()
            let message = OutgoingMessage(push, ref: ref)

            guard message.joinRef != nil else {
                // if we weren't able to get a joinRef for a channel
                // then we will wait and try again in a short bit becuase
                // we might be in the middle of joining or something
                pending.append((retries: 0, ref: ref, push: push))
                retryLater()
                return ref
            }

            tracked.append((.channel(push), message))
            receiveCurrentBatchSoon()
            return ref
        }
    }

    func send(_ push: Socket.Push) -> Ref {
        sync {
            let ref = generator.advance()
            let message = OutgoingMessage(push, ref: ref)
            tracked.append((.socket(push), message))
            receiveCurrentBatchSoon()
            return ref
        }
    }

    private func retryLater() {
        sync {
            guard !willRetryLater else { return }
            willRetryLater = true
        }

        let deadline = DispatchTime.now().advanced(by: .seconds(1))

        DispatchQueue.global().asyncAfter(deadline: deadline) {
            self.retryPending()
        }
    }

    private func retryPending() {
        sync {
            let _pending = pending

            pending.removeAll()

            for (retries: retries, ref: ref, push: push) in _pending {
                let message = OutgoingMessage(push, ref: ref)

                guard message.joinRef != nil else {
                    guard retries < Pusher.maximumRetries else {
                        push.asyncCallback(result: .failure(Channel.ChannelError.isClosed))
                        break
                    }

                    pending.append((retries: retries + 1, ref: ref, push: push))
                    break
                }

                tracked.append((Push(push), message))
            }
        }
    }

//        private func flushLater() {
//            sync {
//                guard !willFlushLater else { return }
//                willFlushLater = true
//            }
//
//            // TODO: make deadline smart

//
//            DispatchQueue.global().asyncAfter(deadline: deadline) {
//                self.flush()
//            }
//        }
//
//        private func flush() {
//            sync {
//                guard isJoined else {
//                    flushLater()
//                    return
//                }
//            }
//
//            var pending: [Channel.Push] = []
//
//            sync {
//                pending = pendingPushes
//                pendingPushes.removeAll()
//            }
//
//            for push in pending { flushOne(push) }
//
//            sync {
//                if pendingPushes.count > 1 {
//                    flushLater()
//                }
//            }
//        }
//
//        private func flushOne(_ push: Channel.Push) {
//            sync {
//                guard isJoined else {
//                    pendingPushes.append(push) // re-insert
//                    return
//                }
//            }
//
//            let ref = socket.generator.advance()
//            let message = OutgoingMessage(push, ref: ref)
//
//            sync {
//                trackedPushes[ref] = (message, push)
//            }
//
//            socket.send(message) { error in
//                if let error = error {
//                    self.change(to: .errored(error))
//                }
//            }
//        }
}
