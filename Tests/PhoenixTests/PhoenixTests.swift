import XCTest
@testable import Phoenix

//private class Delegate: SocketDelegate {
//    var joined = Array<String>()
//    var receivedReplies = Array<Phoenix.Reply>()
//    var receivedMessages = Array<Phoenix.Message>()
//
//    func didJoin(topic: String) {
//        joined.append(topic)
//    }
//
//    func didReceive(reply: Phoenix.Reply) {
//        receivedReplies.append(reply)
//    }
//
//    func didReceive(message: Phoenix.Message) {
//        receivedMessages.append(message)
//    }
//
//    func didLeave(topic: String) {
//        guard let index = joined.lastIndex(of: topic) else { return XCTFail() }
//        joined.remove(at: index)
//    }
//}

class PhoenixTests: XCTestCase {
//    private var websocket: FakeWebSocket!
//    private var phoenix: Socket!
//    private var delegate: Delegate!
//
//    private let topic = "Test"
//
//    private lazy var queue: DispatchQueue = {
//        return DispatchQueue(label: "PhoenixTests")
//    }()
//
//    override func setUp() {
//        super.setUp()
//        websocket = FakeWebSocket(url: URL(string: "127.0.0.1")!)
//        delegate = Delegate()
//        phoenix = Socket(websocket: websocket, delegate: delegate, delegateQueue: queue)
//    }
//
//    func testConnectJoinsChannel() {
//        websocket.onConnect = { $0.sendConnectFromServer() }
//        websocket.onWriteData = { websocket, _ in
//            let message = IncomingMessage(
//                joinRef: 1, ref: 1, topic: self.topic, event: .reply, payload: ["status": "ok"]
//            )
//            websocket.sendMessageFromServer(message)
//        }
//        phoenix.connect()
//        wait { [topic] == $1.joined }
//    }
//
//    func testSendNewMessage() {
//        connect()
//        let message = IncomingMessage(
//            joinRef: 1, ref: 2, topic: topic, event: "phx_msg", payload: ["status": "ok", "key": "value"]
//        )
//        websocket.sendMessageFromServer(message)
//        wait { websocket, delegate in
//            guard let received = delegate.receivedMessages.first else { return false }
//            return isMessage(received, equalTo: message)
//        }
//    }
//
//    func testReply() {
//        connect()
//
//        let push = Push(
//            topic: topic, event: "message:create",
//            payload: ["id": "123", "user_id": "456", "text": "This is message text"]
//        )
//
//        var message = Message(topic: topic, event: "message:create", payload: [:])
//        let reply = Reply(joinRef: 1, ref: 2, message: message, status: "ok", response: [:])
//
//        websocket.onWriteData = { [unowned self] websocket, data in
//            guard let sent = try? Message(data: data) else { return XCTFail() }
//            let expected = Message(
//                joinRef: 1, ref: 2, topic: self.topic, event: push.event, payload: push.payload
//            )
//            XCTAssertTrue(self.isMessage(sent, equalTo: expected))
//            websocket.sendMessageFromServer(reply)
//        }
//
//        phoenix.push(event: push.event, payload: push.payload)
//
//        wait { websocket, delegate in
//            guard let (incoming, outgoing) = delegate.receivedReplies.first else { return false }
//            return isMessage(incoming, equalTo: reply) && isPush(outgoing, equalTo: push)
//        }
//    }
//}
//
//private extension PhoenixTests {
//    func connect() {
//        websocket.onConnect = { $0.sendConnectFromServer() }
//        websocket.onWriteData = { websocket, _ in
//            let message = Message(
//                ref: 1, topic: self.topic, event: "phx_reply", payload: ["status": "ok"]
//            )
//            websocket.sendMessageFromServer(message)
//        }
//        phoenix.connect()
//        wait { [topic] == $1.joined }
//
//        delegate.joined = []
//        delegate.receivedReplies = []
//        delegate.receivedMessages = []
//    }
//
//    func json(ref: Int, joinRef: Int? = nil, payload: Dictionary<String, Any>) -> Dictionary<String, Any> {
//        var json: Dictionary<String, Any> = ["ref": ref, "topic": topic, "payload": payload]
//        if let joinRef = joinRef { json["join_ref"] = joinRef }
//        return json
//    }
//
//    func wait(until test: (FakeWebSocket, Delegate) -> Bool) {
//        let start = CFAbsoluteTimeGetCurrent()
//        let max = start + 0.2
//
//        while CFAbsoluteTimeGetCurrent() < max {
//            if test(self.websocket, self.delegate) {
//                return
//            } else {
//                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
//            }
//        }
//
//        XCTFail()
//    }
//
//    func isPush(_ push: Push, equalTo other: Push) -> Bool {
//        guard push.topic == other.topic else { return false }
//        guard push.event == other.event else { return false }
//        guard push.ref == other.ref else { return false }
//        guard let payload = push.payload as? Dictionary<String, String> else { return false }
//        guard let otherPayload = other.payload as? Dictionary<String, String> else { return false }
//        return payload == otherPayload
//    }
//
//    func isMessage(_ message: Message, equalTo other: Message) -> Bool {
//        guard message.topic == other.topic else { return false }
//        guard message.event == other.event else { return false }
//        guard message.ref == other.ref else { return false }
//        guard message.joinRef == other.joinRef else { return false }
//        guard message.status == other.status else { return false }
//        guard let payload = message.payload as? Dictionary<String, String> else { return false }
//        guard let otherPayload = message.payload as? Dictionary<String, String> else { return false }
//        return payload == otherPayload
//    }
}
