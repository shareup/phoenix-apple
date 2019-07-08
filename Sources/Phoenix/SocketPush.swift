import Foundation

extension Socket {
    struct Push {
        public let topic: String
        public let event: PhxEvent
        public let payload: Payload
    }
}
