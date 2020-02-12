import Foundation

extension Channel {
    struct PushedMessage: Comparable {
        let push: Push
        let message: OutgoingMessage
        
        var ref: Ref { message.ref }
        var joinRef: Ref? { message.joinRef }
        
        var timeoutDate: Date {
            message.sentAt.advanced(by: push.timeout)
        }
        
        func callback(reply: Channel.Reply) {
            push.asyncCallback(result: .success(reply))
        }
        
        func callback(error: Swift.Error) {
            push.asyncCallback(result: .failure(error))
        }
        
        static func < (lhs: Self, rhs: Self) -> Bool {
            return lhs.timeoutDate < rhs.timeoutDate
        }
        
        static func == (lhs: Self, rhs: Self) -> Bool {
            return lhs.timeoutDate == rhs.timeoutDate
        }
    }
}
