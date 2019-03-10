import XCTest
@testable import Phoenix

private class Delegate: PhoenixDelegate {
    var joined = Array<String>()
    var receivedReplies = Array<(Phoenix.Message, Phoenix.Push)>()
    var receivedMessages = Array<Phoenix.Message>()

    func didJoin(topic: String) {
        joined.append(topic)
    }

    func didReceive(reply: Phoenix.Message, for push: Phoenix.Push) {
        receivedReplies.append((reply, push))
    }

    func didReceive(message: Phoenix.Message) {
        receivedMessages.append(message)
    }

    func didLeave(topic: String) {
        guard let index = joined.lastIndex(of: topic) else { return XCTFail() }
        joined.remove(at: index)
    }
}

class PhoenixTests: XCTestCase {
    private var websocket: FakeWebSocket!
    private var phoenix: Phoenix!
    private var delegate: Delegate!

    private let topic = "Test"

    private lazy var queue: DispatchQueue = {
        return DispatchQueue(label: "PhoenixTests")
    }()

    override func setUp() {
        super.setUp()
        websocket = FakeWebSocket(url: URL(string: "127.0.0.1")!)
        delegate = Delegate()
        phoenix = Phoenix(websocket: websocket, topic: topic, delegate: delegate, delegateQueue: queue)
    }

    func testConnect() {
        websocket.onConnect = { $0.sendConnectFromServer() }
        websocket.onWriteData = { websocket, _ in
            websocket.sendReplyFromServer(self.json(ref: 1, payload: ["status": "ok"]))
        }
        
        phoenix.connect()
        wait { [topic] == $1.joined }
    }
}

private extension PhoenixTests {
    func json(ref: Int, joinRef: Int? = nil, payload: Dictionary<String, Any>) -> Dictionary<String, Any> {
        var json: Dictionary<String, Any> = ["ref": ref, "topic": topic, "payload": payload]
        if let joinRef = joinRef { json["join_ref"] = joinRef }
        return json
    }

    func wait(until test: (FakeWebSocket, Delegate) -> Bool) {
        let start = CFAbsoluteTimeGetCurrent()
        let max = start + 0.2

        while CFAbsoluteTimeGetCurrent() < max {
            if test(self.websocket, self.delegate) {
                return
            } else {
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
            }
        }

        XCTFail()
    }
}
