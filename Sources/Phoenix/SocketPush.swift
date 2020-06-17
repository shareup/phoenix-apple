import Foundation

extension Socket {
    public typealias Callback = (Swift.Error?) -> Void
    
    struct Push {
        public let topic: Topic
        public let event: PhxEvent
        public let payload: Payload
        public let callback: Callback?
        
        init(topic: Topic, event: PhxEvent, payload: Payload = [:], callback: Callback? = nil) {
            self.topic = topic
            self.event = event
            self.payload = payload
            self.callback = callback
        }

        func asyncCallback(_ error: Swift.Error?) {
            if let cb = callback {
                DispatchQueue.global().async { cb(error) }
            }
        }
    }
}
