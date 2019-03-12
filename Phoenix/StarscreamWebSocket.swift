import Foundation
import Starscream

public final class StarscreamWebSocket: WebSocketProtocol {
    public weak var delegate: WebSocketDelegateProtocol?
    
    public var callbackQueue: DispatchQueue {
        get { return _socket.callbackQueue }
        set { _socket.callbackQueue = newValue }
    }

    private let _socket: WebSocket

    public required init(url: URL) {
        _socket = WebSocket(url: url)
        _socket.delegate = self
    }

    deinit {
        _socket.delegate = nil
        _socket.disconnect()
    }

    public func connect() {
        _socket.connect()
    }

    public func disconnect() {
        _socket.disconnect()
    }

    public func write(data: Data) {
        _socket.write(data: data)
    }
}

extension StarscreamWebSocket: WebSocketDelegate {
    public func websocketDidConnect(socket: WebSocketClient) {
        delegate?.didConnect(websocket: self)
    }

    public func websocketDidDisconnect(socket: WebSocketClient, error: Error?) {
        delegate?.didDisconnect(websocket: self, error: error)
    }

    public func websocketDidReceiveMessage(socket: WebSocketClient, text: String) {
        delegate?.didReceiveMessage(websocket: self, text: text)
    }

    public func websocketDidReceiveData(socket: WebSocketClient, data: Data) {
        delegate?.didReceiveData(websocket: self, data: data)
    }
}
