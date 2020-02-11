extension Socket {
    enum State {
        case closed
        case connecting(WebSocket)
        case open(WebSocket)
        case closing(WebSocket)
    }
}
