import Foundation
import JSON
import WebSocket

public struct Message: Hashable, Sendable, CustomStringConvertible {
    enum DecodingError: Error {
        case invalidType(String)
        case missingValue(String)
        case invalidTypeForValue(String, String)
    }

    public var joinRef: Ref?
    public var ref: Ref?
    public var topic: Topic
    public var event: Event
    public var payload: JSON

    init(string: String) throws {
        try self.init(data: Data(string.utf8))
    }

    public init(_ msg: WebSocketMessage) throws {
        switch msg {
        case let .data(data):
            try self.init(data: data)
        case let .text(text):
            guard let data = text.data(using: .utf8)
            else { throw PhoenixError.couldNotDecodeMessage }
            try self.init(data: data)
        }
    }

    init(data: Data) throws {
        let jsonArray = try JSONSerialization.jsonObject(with: data, options: [])

        guard let arr = jsonArray as? [Any?] else {
            throw DecodingError.invalidType(String(describing: jsonArray))
        }

        let joinRef: Ref? = _ref(arr[0])
        let ref: Ref? = _ref(arr[1])

        guard let topic = arr[2] as? Topic else {
            throw DecodingError.missingValue("topic")
        }

        guard let eventName = arr[3] as? String else {
            throw DecodingError.missingValue("event")
        }

        let event = Event(eventName)

        guard let payload = arr[4] as? [String: Any?] else {
            throw DecodingError.invalidTypeForValue(
                "payload",
                String(describing: arr[4])
            )
        }

        self.init(
            joinRef: joinRef,
            ref: ref,
            topic: topic,
            event: event,
            payload: JSON(payload)
        )
    }

    public init(
        joinRef: Ref? = nil,
        ref: Ref?,
        topic: Topic,
        event: Event,
        payload: JSON = [:]
    ) {
        self.joinRef = joinRef
        self.ref = ref
        self.topic = topic
        self.event = event
        self.payload = payload
    }

    public var description: String {
        "[\(topic), \(event), \(String(describing: joinRef)), \(String(describing: ref))]"
    }
}

public extension Message {
    @Sendable
    static func decode(_ raw: WebSocketMessage) throws -> Message {
        try Message(raw)
    }
}

public extension Message {
    var reply: (isOk: Bool, response: JSON) {
        get throws {
            let refAndReply = try refAndReply
            return (refAndReply.1, refAndReply.2)
        }
    }

    internal var refAndReply: (Ref, Bool, JSON) {
        get throws {
            guard event == .reply,
                  let ref,
                  case let .string(status) = payload["status"]
            else { throw PhoenixError.invalidReply }

            return (ref, status == "ok", payload["response"] ?? [:])
        }
    }

    var errorPayload: JSON? {
        guard event == .reply,
              case let .string(status) = payload["status"],
              status == "error"
        else { return nil }

        return payload["response"]?["error"] ?? [:]
    }
}

public extension Message {
    var isPhoenixError: Bool {
        guard event == .error else { return false }
        return true
    }
}

private func _ref(_ object: Any?) -> Ref? {
    guard let object else { return nil }

    if let intValue = object as? UInt64 {
        return Ref(intValue)
    } else if let stringValue = object as? String, let intValue = UInt64(stringValue) {
        return Ref(intValue)
    } else {
        return nil
    }
}
