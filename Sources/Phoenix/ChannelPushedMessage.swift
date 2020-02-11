extension Channel {
    struct PushedMessage {
        let push: Push
        let message: OutgoingMessage
        
        var joinRef: Ref? { message.joinRef }
        
        func callback(reply: Channel.Reply) {
            push.asyncCallback(result: .success(reply))
        }
        
        func callback(error: Swift.Error) {
            push.asyncCallback(result: .failure(error))
        }
    }
}
