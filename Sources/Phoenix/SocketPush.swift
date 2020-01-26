import Foundation

extension Socket {
    public typealias Callback = (Swift.Error?) -> Void
    
    struct Push {
        public let topic: String
        public let event: PhxEvent
        public let payload: Payload
        public let callback: Callback?

        func asyncCallback(_ error: Swift.Error?) {
            if let cb = callback {
                DispatchQueue.global().async { cb(error) }
            }
        }
    }
}
