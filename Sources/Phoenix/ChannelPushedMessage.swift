import Foundation

extension Channel {
    struct PushedMessage {
        let push: Push
        let message: OutgoingMessage

        var ref: Ref { message.ref }
        var joinRef: Ref? { message.joinRef }

        var timeoutDate: DispatchTime {
            message.sentAt.advanced(by: push.timeout)
        }

        func callback(reply: Channel.Reply) {
            push.asyncCallback(result: .success(reply))
        }

        func callback(error: Swift.Error) {
            push.asyncCallback(result: .failure(error))
        }
    }
}

extension Sequence<Channel.PushedMessage> {
    func sortedByTimeoutDate() -> [Self.Element] {
        sorted(by: { $0.timeoutDate < $1.timeoutDate })
    }
}
