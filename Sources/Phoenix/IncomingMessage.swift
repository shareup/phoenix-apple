import Foundation

internal struct IncomingMessage {
    enum DecodingError: Error {
        case invalidType(Any?)
        case missingValue(String)
        case invalidTypeForValue(String, Any?)
    }

    let joinRef: Ref?
    let ref: Ref?
    let topic: String
    let event: Event
    let payload: Dictionary<String, Any>

    init(data: Data) throws {
        let jsonArray = try JSONSerialization.jsonObject(with: data, options: [])
        guard let arr = jsonArray as? Array<Any?> else {
            throw DecodingError.invalidType(jsonArray)
        }

        let joinRef: Ref? = _ref(arr[0])
        let ref: Ref? = _ref(arr[1])

        guard let topic = arr[2] as? String else {
            throw DecodingError.missingValue("topic")
        }

        guard let eventName = arr[3] as? String else {
            throw DecodingError.missingValue("event")
        }

        let event = Phoenix.Event(eventName)

        guard let payload = arr[4] as? Payload else {
            throw DecodingError.invalidTypeForValue("payload", arr[4])
        }

        self.init(
            joinRef: joinRef,
            ref: ref,
            topic: topic,
            event: event,
            payload: payload
        )
    }

    init(joinRef: Ref? = nil, ref: Ref?, topic: String, event: Event, payload: Dictionary<String, Any> = [:]) {
        self.joinRef = joinRef
        self.ref = ref
        self.topic = topic
        self.event = event
        self.payload = payload
    }

    func encoded() throws -> Data {
        return try JSONSerialization.data(withJSONObject: asArray(), options: [])
    }

    func asArray() -> Array<Any?> {
        return [
            joinRef?.rawValue,
            ref?.rawValue,
            topic,
            event.stringValue,
            payload
        ]
    }
}

fileprivate func _ref(_ object: Any?) -> Phoenix.Ref? {
    guard let object = object else { return nil }

    if let intValue = object as? UInt64 {
        return Phoenix.Ref(intValue)
    } else if let stringValue = object as? String, let intValue = UInt64(stringValue) {
        return Phoenix.Ref(intValue)
    } else {
        return nil
    }
}
