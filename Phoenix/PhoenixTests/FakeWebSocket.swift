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

    func sendReplyFromServer(_ json: Dictionary<String, Any>) {
        var json = json
        json["event"] = "phx_reply"
        sendFromServer(json)
    }

    private func sendFromServer(_ json: Dictionary<String, Any>) {
        let data = try! JSONSerialization.data(withJSONObject: json, options: [])
        let text = String(data: data, encoding: .utf8)!
        callbackQueue.async { [unowned self] in
            self.delegate?.didReceiveMessage(websocket: self, text: text)
        }
    }
}
