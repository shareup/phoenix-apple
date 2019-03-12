import Foundation
@testable import Phoenix

class FakeWebSocket: WebSocketProtocol {
    var callbackQueue: DispatchQueue = .main
    var delegate: WebSocketDelegateProtocol?

    let url: URL

    var onConnect: (FakeWebSocket) -> Void = { _ in }
    var onDisconnect: (FakeWebSocket, Error?) -> Void = { _, _ in }
    var onWriteData: (FakeWebSocket, Data) -> Void = { _, _ in }

    required init(url: URL) {
        self.url = url
    }

    func connect() {
        onConnect(self)
    }

    func disconnect() {
        onDisconnect(self, nil)
    }

    func disconnect(with error: Error) {
        onDisconnect(self, error)
    }

    func write(data: Data) {
        onWriteData(self, data)
    }

    func sendConnectFromServer() {
        callbackQueue.async { [unowned self] in
            self.delegate?.didConnect(websocket: self)
        }
    }

    func sendDisconnectFromServer(error: Error? = nil) {
        callbackQueue.async { [unowned self] in
            self.delegate?.didDisconnect(websocket: self, error: error)
        }
    }

    func sendMessageFromServer(_ message: Phoenix.Message) {
        callbackQueue.async { [unowned self] in
            let data = try! message.encoded()
            let text = String(data: data, encoding: .utf8)!
            self.delegate?.didReceiveMessage(websocket: self, text: text)
        }
    }
}
