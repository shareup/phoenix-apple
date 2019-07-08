import Foundation

extension Socket {
    struct Push {
        public let topic: String
        public let event: Event
        public let payload: [String: Codable]
    }
}
