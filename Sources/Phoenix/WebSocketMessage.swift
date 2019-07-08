import Foundation

extension WebSocket {
    public enum Message {
        case data(Data)
        case string(String)
        case open
        
        init(_ message: URLSessionWebSocketTask.Message) {
            switch message {
            case .data(let data):
                self = .data(data)
            case .string(let string):
                self = .string(string)
            @unknown default:
                assertionFailure("Unknown WebSocket Message type")
                self = .string("")
            }
        }
    }
}
