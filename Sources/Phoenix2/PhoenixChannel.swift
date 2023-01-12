import Foundation
import os.log
import Synchronized

final class PhoenixChannel {
    let topic: Topic
    let joinPayload: Payload

    private let socket: PhoenixSocket

    private let state = Locked(State.closed)

    init(
        topic: Topic,
        joinPayload: Payload = [:],
        socket: PhoenixSocket
    ) {
        self.topic = topic
        self.joinPayload = joinPayload
        self.socket = socket
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
            switch state {
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

private enum State {
    case closed
    case errored
    case joined(Ref, reply: Payload?)
    case joining
    case leaving

    var joinRef: Ref? {
        switch self {
        case .closed, .errored, .joining, .leaving:
            return nil

        case let .joined(ref, _):
            return ref
        }
    }
}
