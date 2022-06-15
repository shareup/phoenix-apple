import Foundation

public enum Payload: Hashable, Sendable, ExpressibleByDictionaryLiteral,
    CustomStringConvertible
{
    public typealias Key = String
    public typealias Value = Any?

    indirect case array([Payload])
    case boolean(Bool)
    indirect case dictionary([String: Payload])
    case number(Double)
    case null
    case string(String)

    public init(_ dictionary: [String: Any?]) {
        self = dictionary.payload
    }

    public init(dictionaryLiteral elements: (String, Any?)...) {
        var dictionary = [String: Payload]()
        for (key, value) in elements {
            guard let v = value.payload else { continue }
            dictionary[key] = v
        }
        self = .dictionary(dictionary)
    }

    public var jsonValue: Any {
        switch self {
        case let .array(array):
            return array.map(\.jsonValue)

        case let .boolean(bool):
            return bool

        case let .dictionary(dictionary):
            return dictionary.mapValues(\.jsonValue)

        case let .number(number):
            return number

        case .null:
            return NSNull()

        case let .string(string):
            return string
        }
    }

    /// Returns a `Dictionary<String, Any>` representation of the received.
    /// The returned value is suitable for encoding as JSON via
    /// `JSONSerialization.data(withJSONObject:options:)`.
    ///
    /// This method calls `preconditionFailure()` if the receiver is not
    /// of type `.dictionary`.
    public var jsonDictionary: [String: Any] {
        guard let json = jsonValue as? [String: Any]
        else { preconditionFailure("\(self) must be a dictionary") }

        return json
    }

    public var description: String {
        String(describing: jsonValue)
    }
}

extension Array where Element == Any? {
    var payload: Payload {
        .array(compactMap(\.payload))
    }
}

public extension Dictionary where Key == String, Value == Any? {
    var payload: Payload {
        var dictionary = [String: Payload]()
        for (key, value) in self {
            guard let v = value.payload else { continue }
            dictionary[key] = v
        }
        return .dictionary(dictionary)
    }
}

private extension Optional where Wrapped == Any {
    var payload: Payload? {
        guard case let .some(element) = self else { return .null }

        switch element {
        case let e as [Any?]: return e.payload
        case let e as [String: Any?]: return e.payload
        case is NSNull: return .null
        case let e as NSNumber where e.isBool: return .boolean(e.boolValue)
        case let e as NSNumber: return .number(e.doubleValue)
        case let e as String: return .string(e)

        // The above cases should catch everything, but, in case they
        // don't, we try remaining types here.
        case let e as Bool: return .boolean(e)
        case let e as Double: return .number(e)
        case let e as Int: return .number(Double(e))

        default: return nil
        }
    }
}

private extension NSNumber {
    var isBool: Bool {
        CFBooleanGetTypeID() == CFGetTypeID(self)
    }
}
