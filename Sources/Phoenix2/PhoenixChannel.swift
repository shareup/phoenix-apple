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

private struct Join {
    let ref: Ref
    let reply: Payload?
}
