import Foundation

extension Socket {
    public typealias Callback = (Swift.Error?) -> Void
    
    struct Push {
        public let topic: String
        public let event: PhxEvent
        public let payload: Payload
        public let timeout: Int
        public let callback: Callback?
        
        init(topic: String, event: PhxEvent, payload: Payload = [:], timeout: Int = Socket.defaultTimeout, callback: Callback? = nil) {
            self.topic = topic
            self.event = event
            self.payload = payload
            self.timeout = timeout
            self.callback = callback
        }

        func asyncCallback(_ error: Swift.Error?) {
            if let cb = callback {
                DispatchQueue.global().async { cb(error) }
            }
        }
    }
}
