import Foundation

extension Socket {
    struct Push {
        typealias Callback = (Error?) -> Void

        public let topic: String
        public let event: PhxEvent
        public let payload: Payload
        public let callback: Callback?

        func asyncCallback(_ error: Error?) {
            if let cb = callback {
                DispatchQueue.global().async { cb(error) }
            }
        }
    }
}
