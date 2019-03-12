import Foundation

extension Phoenix {
    public struct Message {
        public enum DecodingError: Error {
            case invalidType(Any)
            case missingValue(String)
        }

        public let joinRef: Ref?
        public let ref: Ref?
        public let topic: String
        public let event: Event
        public let payload: Dictionary<String, Any>

        public var status: String? { return payload["status"] as? String }
        public var isOk: Bool { return status == "ok" }
        public var isNotOk: Bool { return isOk == false }

        public init(data: Data) throws {
            let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
            guard let dict = jsonObject as? Dictionary<String, Any> else {
                throw DecodingError.invalidType(jsonObject)
            }

            guard let topic = Decoder.topic(from: dict) else { throw DecodingError.missingValue("topic") }
            guard let event = Decoder.event(from: dict) else { throw DecodingError.missingValue("event") }

            self.init(
                joinRef: Decoder.joinRef(from: dict),
                ref: Decoder.ref(from: dict),
                topic: topic,
                event: event,
                payload: Decoder.payload(from: dict)
            )
        }

        public init(joinRef: Ref? = nil, ref: Ref?, topic: String, event: Event, payload: Dictionary<String, Any> = [:]) {
            self.joinRef = joinRef
            self.ref = ref
            self.topic = topic
            self.event = event
            self.payload = payload
        }

        func encoded() throws -> Data {
            return try JSONSerialization.data(withJSONObject: asDictionary(), options: [])
        }

        private func asDictionary() -> Dictionary<String, Any> {
            var dict: Dictionary<String, Any> = [
                "topic": topic,
                "event": event.stringValue,
                "payload": payload
            ]

            if let joinRef = self.joinRef {
                dict["join_ref"] = joinRef.rawValue
            }

            if let ref = self.ref {
                dict["ref"] = ref.rawValue
            }

            return dict
        }
    }
}

private struct Decoder {
    static func joinRef(from dictionary: Dictionary<String, Any>) -> Phoenix.Ref? {
        return _ref(from: dictionary, key: "join_ref")
    }

    static func ref(from dictionary: Dictionary<String, Any>) -> Phoenix.Ref? {
        return _ref(from: dictionary, key: "ref")
    }

    static func topic(from dictionary: Dictionary<String, Any>) -> String? {
        return dictionary["topic"] as? String
    }

    static func event(from dictionary: Dictionary<String, Any>) -> Phoenix.Event? {
        guard let event = dictionary["event"] as? String else { return nil }
        return Phoenix.Event(event)
    }

    static func payload(from dictionary: Dictionary<String, Any>) -> Dictionary<String, Any> {
        guard let payload = dictionary["payload"] else { return [:] }
        guard let dict = payload as? Dictionary<String, Any> else { return [:] }
        return dict
    }

    private static func _ref(from dictionary: Dictionary<String, Any>, key: String) -> Phoenix.Ref? {
        guard let object = dictionary[key] else { return nil }

        if let intValue = object as? UInt64 {
            return Phoenix.Ref(intValue)
        } else if let stringValue = object as? String, let intValue = UInt64(stringValue) {
            return Phoenix.Ref(intValue)
        } else {
            return nil
        }
    }
}
