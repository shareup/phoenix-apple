import Foundation

extension Phoenix {
    public struct Push {
        public let ref: Ref
        public let topic: String
        public let event: Event
        public let payload: Dictionary<String, Any>

        public init(ref: Ref, topic: String, event: Event, payload: Dictionary<String, Any> = [:]) {
            self.ref = ref
            self.topic = topic
            self.event = event
            self.payload = payload
        }

        func encoded(with joinRef: Ref? = nil) throws -> Data {
            return try JSONSerialization.data(withJSONObject: asDictionary(with: joinRef), options: [])
        }

        private func asDictionary(with joinRef: Ref? = nil) -> Dictionary<String, Any> {
            var dict: Dictionary<String, Any> = [
                "ref": ref.rawValue,
                "topic": topic,
                "event": event.stringValue,
                "payload": payload
            ]

            if let joinRef = joinRef {
                dict["join_ref"] = joinRef.rawValue
            }

            return dict
        }
    }
}

