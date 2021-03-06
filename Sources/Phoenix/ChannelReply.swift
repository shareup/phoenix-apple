public extension Channel {
    struct Reply {
        public struct Error: Swift.Error {
            let message: String
        }

        let incomingMessage: IncomingMessage
        let ref: Ref
        let status: String

        var joinRef: Ref? { incomingMessage.joinRef }

        public let response: [String: Any]

        public init?(incomingMessage: IncomingMessage) {
            guard incomingMessage.event == .reply,
                  let ref = incomingMessage.ref,
                  let status = incomingMessage.payload["status"] as? String,
                  let response = incomingMessage.payload["response"] as? [String: Any]
            else {
                return nil
            }

            self.incomingMessage = incomingMessage
            self.ref = ref
            self.status = status
            self.response = response
        }

        public var isOk: Bool { status == "ok" }
        public var isNotOk: Bool { isOk == false }

        public var error: Error? {
            guard isNotOk,
                  let err = response["error"] as? String
            else {
                return nil
            }

            return Error(message: err)
        }

        public var message: Channel.Message { .init(incomingMessage: incomingMessage) }
    }
}
