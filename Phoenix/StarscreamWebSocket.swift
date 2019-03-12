import Foundation
import Starscream

class StarscreamWebSocket: WebSocketProtocol {
    weak var delegate: WebSocketDelegateProtocol?
    
    var callbackQueue: DispatchQueue {
        get { return _socket.callbackQueue }
        set { _socket.callbackQueue = newValue }
    }

    private let _socket: WebSocket

    required init(url: URL) {
        _socket = WebSocket(url: url)
        _socket.delegate = self
    }

    deinit {
        _socket.delegate = nil
        _socket.disconnect()
    }

    func connect() {
        _socket.connect()
    }

    func disconnect() {
        _socket.disconnect()
    }

    func write(data: Data) {
        _socket.write(data: data)
    }
}

extension StarscreamWebSocket: WebSocketDelegate {
    func websocketDidConnect(socket: WebSocketClient) {
        delegate?.didConnect(websocket: self)
    }

    func websocketDidDisconnect(socket: WebSocketClient, error: Error?) {
        delegate?.didDisconnect(websocket: self, error: error)
    }

    func websocketDidReceiveMessage(socket: WebSocketClient, text: String) {
        delegate?.didReceiveMessage(websocket: self, text: text)
    }

    func websocketDidReceiveData(socket: WebSocketClient, data: Data) {
        delegate?.didReceiveData(websocket: self, data: data)
    }
}
