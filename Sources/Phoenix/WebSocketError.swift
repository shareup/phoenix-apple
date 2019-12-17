import Foundation

public enum WebSocketError: Error {
    case unopened
    case invalidURL(URL)
    case invalidURLComponents(URLComponents)
    case notOpen
    case closed(URLSessionWebSocketTask.CloseCode, Data?)
}
