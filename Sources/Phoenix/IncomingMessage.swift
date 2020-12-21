import Foundation
import WebSocketProtocol

public enum RawIncomingMessage: CustomStringConvertible, Hashable {
    case binary(Data)
    case text(String)

    public var description: String {
        switch self {
        case let .binary(data): return String(data: data, encoding: .utf8) ?? ""
        case let .text(text): return text
        }
    }
}

public struct IncomingMessage: CustomDebugStringConvertible {
    enum DecodingError: Error {
        case invalidType(Any?)
        case missingValue(String)
        case invalidTypeForValue(String, Any?)
    }

    public var joinRef: Ref?
    public var ref: Ref?
    public var topic: Topic
    public var event: PhxEvent
    public var payload: Payload
    
    init(string: String) throws {
        try self.init(data: Data(string.utf8))
    }

    public init(_ rawMessage: RawIncomingMessage) throws {
        switch rawMessage {
        case let .binary(data):
            try self.init(data: data)
        case let .text(text):
            try self.init(data: try text.data(using: .utf8))
        }
    }

    init(data: Data) throws {
        let jsonArray = try JSONSerialization.jsonObject(with: data, options: [])

        guard let arr = jsonArray as? [Any?] else {
            throw DecodingError.invalidType(jsonArray)
        }

        let joinRef: Ref? = _ref(arr[0])
        let ref: Ref? = _ref(arr[1])

        guard let topic = arr[2] as? Topic else {
            throw DecodingError.missingValue("topic")
        }

        guard let eventName = arr[3] as? String else {
            throw DecodingError.missingValue("event")
        }

        let event = PhxEvent(eventName)

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

    public init(
        joinRef: Ref? = nil,
        ref: Ref?,
        topic: Topic,
        event: PhxEvent,
        payload: Payload = [:]
    ) {
        self.joinRef = joinRef
        self.ref = ref
        self.topic = topic
        self.event = event
        self.payload = payload
    }

    public var debugDescription: String {
        let jr = joinRef?.debugDescription ?? "<nil>"
        let r = ref?.debugDescription ?? "<nil>"
        let e = event.stringValue
        let p = "{\(payload.keys.count) values}"
        return "[\(jr),\(r),\"\(topic)\",\"\(e)\",\(p)]"
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
