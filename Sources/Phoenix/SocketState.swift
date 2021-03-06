import WebSocket

extension Socket {
    enum State: CustomStringConvertible {
        case closed
        case connecting(WebSocket)
        case open(WebSocket)
        case closing(WebSocket)

        var webSocket: WebSocket? {
            switch self {
            case .closed:
                return nil
            case let .connecting(ws), let .open(ws), let .closing(ws):
                return ws
            }
        }

        var description: String {
            switch self {
            case .closed: return "closed"
            case .connecting: return "connecting"
            case .open: return "open"
            case .closing: return "closing"
            }
        }
    }
}
