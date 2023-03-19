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

    public subscript(key: String) -> Payload? {
        guard case let .dictionary(dict) = self else { return nil }
        return dict[key]
    }

    public subscript(index: Int) -> Payload? {
        guard case let .array(arr) = self, index < arr.count
        else { return nil }
        return arr[index]
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

extension Payload: Equatable {
    public static func == (_ arg1: Payload, _ arg2: Payload) -> Bool {
        switch (arg1, arg2) {
        case let (.array(one), .array(two)):
            return one == two

        case let (.boolean(one), .boolean(two)):
            return one == two

        case let (.dictionary(one), .dictionary(two)):
            return one == two

        case let (.number(one), .number(two)):
            return one == two

        case (.null, .null):
            return true

        case let (.string(one), .string(two)):
            return one == two

        default:
            return false
        }
    }
}

public extension Payload? {
    static func == (_ arg1: Payload, _ arg2: Payload?) -> Bool {
        guard let arg2 else { return false }
        return arg1 == arg2
    }

    static func == (_ arg1: Payload?, _ arg2: Payload) -> Bool {
        guard let arg1 else { return false }
        return arg1 == arg2
    }

    static func == (_ arg1: String, _ arg2: Payload?) -> Bool {
        guard let arg2, case let .string(unwrapped) = arg2
        else { return false }
        return arg1 == unwrapped
    }

    static func == (_ arg1: Payload?, _ arg2: String) -> Bool {
        guard let arg1, case let .string(unwrapped) = arg1
        else { return false }
        return arg2 == unwrapped
    }

    static func == (_ arg1: Int, _ arg2: Payload?) -> Bool {
        guard let arg2, case let .number(unwrapped) = arg2
        else { return false }
        return arg1 == Int(unwrapped)
    }

    static func == (_ arg1: Payload?, _ arg2: Int) -> Bool {
        guard let arg1, case let .number(unwrapped) = arg1
        else { return false }
        return arg2 == Int(unwrapped)
    }

    static func == (_ arg1: Double, _ arg2: Payload?) -> Bool {
        guard let arg2, case let .number(unwrapped) = arg2
        else { return false }
        return arg1 == unwrapped
    }

    static func == (_ arg1: Payload?, _ arg2: Double) -> Bool {
        guard let arg1, case let .number(unwrapped) = arg1
        else { return false }
        return arg2 == unwrapped
    }

    static func == (_ arg1: Bool, _ arg2: Payload?) -> Bool {
        guard let arg2, case let .boolean(unwrapped) = arg2
        else { return false }
        return arg1 == unwrapped
    }

    static func == (_ arg1: Payload?, _ arg2: Bool) -> Bool {
        guard let arg1, case let .boolean(unwrapped) = arg1
        else { return false }
        return arg2 == unwrapped
    }
}

extension [Any?] {
    var payload: Payload {
        .array(compactMap(\.payload))
    }
}

public extension [String: Any?] {
    var payload: Payload {
        var dictionary = [String: Payload]()
        for (key, value) in self {
            guard let v = value.payload else { continue }
            dictionary[key] = v
        }
        return .dictionary(dictionary)
    }
}

private extension Any? {
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
