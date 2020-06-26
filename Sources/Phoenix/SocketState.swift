extension Socket {
    enum State {
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
    }
}
