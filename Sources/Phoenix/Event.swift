public enum Event: Hashable, ExpressibleByStringLiteral, Sendable {
    case join
    case leave
    case close
    case reply
    case error
    case heartbeat
    case custom(String)

    public init(_ stringValue: String) {
        switch stringValue {
        case "phx_join":
            self = .join
        case "phx_leave":
            self = .leave
        case "phx_close":
            self = .close
        case "phx_reply":
            self = .reply
        case "phx_error":
            self = .error
        case "heartbeat":
            self = .heartbeat
        default:
            self = .custom(stringValue)
        }
    }

    public init(stringLiteral: String) {
        self.init(stringLiteral)
    }

    public var stringValue: String {
        switch self {
        case .join:
            return "phx_join"
        case .leave:
            return "phx_leave"
        case .close:
            return "phx_close"
        case .reply:
            return "phx_reply"
        case .error:
            return "phx_error"
        case .heartbeat:
            return "heartbeat"
        case let .custom(string):
            return string
        }
    }

    public static func == (lhs: Event, rhs: Event) -> Bool {
        lhs.stringValue == rhs.stringValue
    }
}
