import Foundation

protocol WebSocketDelegateProtocol: class {
    func didConnect(websocket: WebSocketProtocol)
    func didDisconnect(websocket: WebSocketProtocol, error: Error?)
    func didReceiveMessage(websocket: WebSocketProtocol, text: String)
    func didReceiveData(websocket: WebSocketProtocol, data: Data)
}

protocol WebSocketProtocol: class {
    var callbackQueue: DispatchQueue { get set }
    var delegate: WebSocketDelegateProtocol? { get set }

    init(url: URL)

    func connect()
    func disconnect()

    func write(data: Data)
}
