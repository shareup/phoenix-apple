import XCTest
import Combine
@testable import Phoenix

class ChannelTests: XCTestCase {
    lazy var socket: Socket = {
        Socket(url: testHelper.defaultURL)
    }()
    
    override func setUp() {
        self.socket = Socket(url: testHelper.defaultURL)
    }
    
    override func tearDown() {
        socket.disconnect()
    }
    
    func testChannelInit() throws {
        let channel = Channel(topic: "rooms:lobby", socket: socket)
        
        XCTAssert(channel.isClosed)
        XCTAssertEqual(channel.connectionState, "closed")
        XCTAssertFalse(channel.joinedOnce)
        XCTAssertEqual(channel.topic, "rooms:lobby")
        XCTAssertEqual(channel.timeout, Socket.defaultTimeout)
    }
    
    func testChannelInitOverrides() throws {
        let socket = Socket(url: testHelper.defaultURL, timeout: .milliseconds(1234))
        
        let channel = Channel(topic: "rooms:lobby", joinPayload: ["one": "two"], socket: socket)
        XCTAssertEqual(channel.joinPayload as? [String: String], ["one": "two"])
        XCTAssertEqual(channel.timeout, .milliseconds(1234))
    }
    
    func testJoinPushPayload() throws {
        let socket = Socket(url: testHelper.defaultURL, timeout: .milliseconds(1234))
        
        let channel = Channel(topic: "rooms:lobby", joinPayload: ["one": "two"], socket: socket)
        
        let push = channel.joinPush
        
        XCTAssertEqual(push.payload as? [String: String], ["one": "two"])
        XCTAssertEqual(push.event, .join)
        XCTAssertEqual(push.timeout, .milliseconds(1234))
    }
    
    func testJoinPushBlockPayload() throws {
        var counter = 1
        
        let block = { () -> Payload in ["number": counter] }
        
        let channel = Channel(topic: "rooms:lobby", joinPayloadBlock: block, socket: socket)
        
        XCTAssertEqual(channel.joinPush.payload as? [String: Int], ["number": 1])
        
        counter += 1
        
        // We've made the explicit decision to realize the joinPush.payload when we construct the joinPush struct
        
        XCTAssertEqual(channel.joinPush.payload as? [String: Int], ["number": 2])
    }
    
    func testIsJoiningAfterJoin() throws {
        let channel = Channel(topic: "rooms:lobby", socket: socket)
        channel.join()
        XCTAssertEqual(channel.connectionState, "joining")
    }
    
    func testJoinTwiceIsNoOp() throws {
        let channel = Channel(topic: "topic", socket: socket)
        
        channel.join()
        channel.join()
    }
    
    func testJoinPushParamsMakeItToServer() throws {
        let params = ["did": "make it"]
        
        let openEx = expectation(description: "Socket should have opened")
        
        let sub = socket.forever {
            if case .open = $0 { openEx.fulfill() }
        }
        defer { sub.cancel() }
        
        socket.connect()
        
        wait(for: [openEx], timeout: 1)
        
        let channel = Channel(topic: "room:lobby", joinPayload: params, socket: socket)
        
        let joinEx = expectation(description: "Shoult have joined")
        
        let sub2 = channel.forever {
            if case .join = $0 { joinEx.fulfill() }
        }
        defer { sub2.cancel() }
        
        channel.join()
        
        wait(for: [joinEx], timeout: 1)
        
        var replyParams: [String: String]? = nil
        
        let replyEx = expectation(description: "Should have received reply")
        
        channel.push("echo_join_params") { result in
            if case .success(let reply) = result {
                replyParams = reply.response as? [String: String]
                replyEx.fulfill()
            }
        }
        
        wait(for: [replyEx], timeout: 1)
        
        XCTAssertEqual(params, replyParams)
    }
    
    func testJoinCanHaveTimeout() throws {
        let channel = Channel(topic: "topic", socket: socket)
        channel.join(timeout: .milliseconds(1234))
        XCTAssertEqual(channel.timeout, .milliseconds(1234))
    }
    
    // MARK: timeout behavior
    
    func testJoinSucceedsIfBeforeTimeout() throws {
        var counter = 0
        let block: Channel.JoinPayloadBlock = { counter += 1; return [:] }
        
        let channel = Channel(topic: "room:lobby", joinPayloadBlock: block, socket: socket)
        
        let joinEx = expectation(description: "Should have joined")
        
        let sub = channel.forever {
            if case .join = $0 { joinEx.fulfill() }
        }
        defer { sub.cancel() }
        
        channel.join(timeout: .seconds(1))
        
        let time = DispatchTime.now().advanced(by: .milliseconds(200))
        DispatchQueue.global().asyncAfter(deadline: time) { [socket] in
            socket.connect()
        }
        
        wait(for: [joinEx], timeout: 2)
        
        XCTAssert(channel.isJoined)
        XCTAssertEqual(counter, 2)
        // The joinPush is generated once and sent to the Socket which isn't open, so it's not written
        // Then a second time after the Socket publishes it's open message and the Channel tries to reconnect
    }
    
    func testJoinRetriesWithBackoffIfTimeout() throws {
        let openEx = expectation(description: "Socket should have opened")

        let sub = socket.forever {
            if case .open = $0 { openEx.fulfill() }
        }
        defer { sub.cancel() }

        socket.connect()

        wait(for: [openEx], timeout: 0.3)

        var counter = 0

        let channel = Channel(
            topic: "room:timeout",
            joinPayloadBlock: {
                counter += 1
                if (counter >= 4) {
                    return ["join": true]
                } else {
                    return ["timeout": 400, "join": true]
                }
            },
            socket: socket)

        let joinEx = expectation(description: "Should have joined")

        let sub2 = channel.forever {
            if case .join = $0 {
                joinEx.fulfill()
            }
        }
        defer { sub2.cancel() }

        channel.join(timeout: .milliseconds(300))

        waitForExpectations(timeout: 15)

        XCTAssert(channel.isJoined)
        XCTAssertEqual(counter, 4)
        // 1st is the first backoff amount of 1 second
        // 2nd is the second backoff amount of 2 seconds
        // 3rd is the third backoff amount of 5 seconds
        // 4th is the successful join, where we don't ask the server to sleep
    }
    
    func testSetsStateToErroredAfterJoinTimeout() throws {
        defer { socket.disconnect() }
        
        let openEx = expectation(description: "Socket should have opened")
        
        let sub = socket.forever {
            if case .open = $0 { openEx.fulfill() }
        }
        defer { sub.cancel() }
        
        socket.connect()
        
        wait(for: [openEx], timeout: 0.5)
        
        // Very large timeout for the server to wait before erroring
        let channel = Channel(topic: "room:timeout", joinPayload: ["timeout": 15_000, "join": true], socket: socket)
        
        let erroredEx = expectation(description: "Channel should not have joined")
        
        let sub2 = channel.forever {
            if case .error = $0 {
                erroredEx.fulfill()
            }
        }
        defer { sub2.cancel() }
        
        // Very short timeout for the joinPush
        channel.join(timeout: .seconds(1))
        
        wait(for: [erroredEx], timeout: 2)
        
        XCTAssertEqual(channel.connectionState, "errored")
    }
    
    // MARK: old tests before https://github.com/shareup/phoenix-apple/pull/4
    
    func skip_testJoinAndLeaveEvents() throws {
        let openMesssageEx = expectation(description: "Should have received an open message")
        
        let socket = Socket(url: testHelper.defaultURL)
        defer { socket.disconnect() }
        
        let sub = socket.forever {
            if case .open = $0 { openMesssageEx.fulfill() }
        }
        defer { sub.cancel() }
        
        socket.connect()
        
        wait(for: [openMesssageEx], timeout: 0.5)
        
        sub.cancel()
        
        let channelJoinedEx = expectation(description: "Channel joined")
        let channelLeftEx = expectation(description: "Channel left")
        
        let channel = socket.join("room:lobby")
        
        let sub2 = channel.forever { result in
            switch result {
            case .join:
                channelJoinedEx.fulfill()
            case .leave:
                channelLeftEx.fulfill()
            default: break
            }
        }
        defer { sub2.cancel() }
        
        wait(for: [channelJoinedEx], timeout: 0.25)
        
        channel.leave()
        
        waitForExpectations(timeout: 0.25)
    }
    
    func skip_testPushCallback() throws {
        let openMesssageEx = expectation(description: "Should have received an open message")
        
        let socket = Socket(url: testHelper.defaultURL)
        defer { socket.disconnect() }
        
        let sub = socket.forever {
            if case .open = $0 { openMesssageEx.fulfill() }
        }
        defer { sub.cancel() }
        
        socket.connect()
        
        wait(for: [openMesssageEx], timeout: 0.5)
        
        let channelJoinedEx = expectation(description: "Channel joined")
        
        let channel = socket.join("room:lobby")
        
        let sub2 = channel.forever { result in
            if case .join = result { channelJoinedEx.fulfill() }
        }
        defer { sub2.cancel() }
        
        socket.connect()
        
        wait(for: [channelJoinedEx], timeout: 0.25)
        
        let repliedOKEx = expectation(description: "Received OK reply")
        let repliedErrorEx = expectation(description: "Received error reply")
        
        channel.push("echo", payload: ["echo": "hello"]) { result in
            guard case .success(let reply) = result else {
                XCTFail()
                return
            }

            XCTAssert(reply.isOk, "Reply should have been OK")
            
            let echo = reply.response["echo"] as? String
            
            XCTAssertEqual(echo, "hello")
            
            repliedOKEx.fulfill()
        }
        
        channel.push("echo_error", payload: ["error": "whatever"]) { result in
            guard case .success(let reply) = result else {
                XCTFail()
                return
            }

            XCTAssert(reply.isNotOk, "Reply should have been not OK")
            
            let error = reply.response["error"] as? String
            
            XCTAssertEqual(error, "whatever")
            
            repliedErrorEx.fulfill()
        }
        
        wait(for: [repliedOKEx, repliedErrorEx], timeout: 0.25)
    }
    
    func skip_testReceiveMessages() throws {
        let openMesssageEx = expectation(description: "Should have received an open message")
        
        let socket = Socket(url: testHelper.defaultURL)
        defer { socket.disconnect() }
        
        let sub = socket.forever {
            if case .open = $0 { openMesssageEx.fulfill() }
        }
        defer { sub.cancel() }
        
        socket.connect()
        
        wait(for: [openMesssageEx], timeout: 0.5)
        
        let channelJoinedEx = expectation(description: "Channel joined")
        let messageRepeatedEx = expectation(description: "Message repeated correctly")
        let echoText = "This should be repeated"
        
        let channel = socket.join("room:lobby")
        var messageCounter = 0
        
        let sub2 = channel.forever { result in
            if case .join = result {
                return channelJoinedEx.fulfill()
            }
            
            if case .message(let message) = result {
                messageCounter += 1
                
                XCTAssertEqual(message.event, "repeated")
                
                let echo = message.payload["echo"] as? String
                XCTAssertEqual(echo, echoText)
                
                if messageCounter >= 5 {
                    messageRepeatedEx.fulfill()
                }
                
                return
            }
        }
        defer { sub2.cancel() }
        
        wait(for: [channelJoinedEx], timeout: 0.25)
        
        let payload: [String: Any] = ["echo": echoText, "amount": 5]
        
        channel.push("repeat", payload: payload)
        
        wait(for: [messageRepeatedEx], timeout: 0.25)
    }
    
    func skip_testMultipleSocketsCollaborating() throws {
        let openMesssageEx1 = expectation(description: "Should have received an open message for socket 1")
        let openMesssageEx2 = expectation(description: "Should have received an open message for socket 2")
        
        let socket1 = Socket(url: testHelper.defaultURL)
        let socket2 = Socket(url: testHelper.defaultURL)
        defer {
            socket1.disconnect()
            socket2.disconnect()
        }
        
        let sub1 = socket1.forever { if case .open = $0 { openMesssageEx1.fulfill() } }
        let sub2 = socket2.forever { if case .open = $0 { openMesssageEx2.fulfill() } }
        defer {
            sub1.cancel()
            sub2.cancel()
        }
        
        socket1.connect()
        socket2.connect()
        
        wait(for: [openMesssageEx1, openMesssageEx2], timeout: 0.5)
        
        let channel1 = socket1.join("room:lobby")
        let channel2 = socket2.join("room:lobby")
        
        let messageText = "This should get broadcasted 😎"
        
        let channel1JoinedEx = expectation(description: "Channel 1 joined")
        let channel2JoinedEx = expectation(description: "Channel 2 joined")
        let channel1ReceivedMessageEx = expectation(description: "Channel 1 received the message")
        let channel2ReceivedMessageEx = expectation(description: "Channel 2 received the message which was not right")
        channel2ReceivedMessageEx.isInverted = true
        
        let sub3 = channel1.forever { result in
            switch result {
            case .join:
                channel1JoinedEx.fulfill()
            case .message(let message):
                let text = message.payload["text"] as? String
                
                if message.event == "message" && text == messageText {
                    return channel1ReceivedMessageEx.fulfill()
                }
            default: break
            }
        }
        defer { sub3.cancel() }
        
        let sub4 = channel2.forever { result in
            switch result {
            case .join:
                channel2JoinedEx.fulfill()
            case .message:
                channel2ReceivedMessageEx.fulfill()
            default: break
            }
        }
        defer { sub4.cancel() }
        
        wait(for: [channel1JoinedEx, channel2JoinedEx], timeout: 0.25)
        
        channel2.push("insert_message", payload: ["text": messageText])
        
        //wait(for: [channel1ReceivedMessageEx], timeout: 0.25)
        waitForExpectations(timeout: 1)
    }
    
    func skip_testRejoinsAfterDisconnect() throws {
        let socket = Socket(url: testHelper.defaultURL)
        defer { socket.disconnect() }
        
        let openMesssageEx = expectation(description: "Should have received an open message twice (once after disconnect)")
        openMesssageEx.expectedFulfillmentCount = 2
        
        let sub = socket.forever {
            if case .open = $0 { openMesssageEx.fulfill() }
        }
        defer { sub.cancel() }
        
        socket.connect()
        
        let channelJoinedEx = expectation(description: "Channel should have joined twice (one after disconnecting)")
        channelJoinedEx.expectedFulfillmentCount = 2
        
        let channel = socket.join("room:lobby")
        
        let sub2 = channel.forever {
            if case .join = $0 {
                socket.send("disconnect")
                channelJoinedEx.fulfill()
            }
        }
        defer { sub2.cancel() }
        
        waitForExpectations(timeout: 1)
    }
    
    // MARK: skipped
    func skip_testDoesntRejoinAfterDisconnectIfLeftOnPurpose() throws {
        let socket = Socket(url: testHelper.defaultURL)
        defer { socket.disconnect() }
        
        let openMesssageEx = expectation(description: "Should have received an open message twice (once after disconnect)")
        openMesssageEx.expectedFulfillmentCount = 2
        
        let sub = socket.forever {
            if case .open = $0 { openMesssageEx.fulfill(); return }
        }
        defer { sub.cancel() }
        
        socket.connect()
        
        let channelJoinedEx = expectation(description: "Channel should have joined once")
        
        let channel = socket.join("room:lobby")
        
        let sub2 = channel.forever {
            if case .join = $0 { channelJoinedEx.fulfill(); return }
        }
        
        wait(for: [channelJoinedEx], timeout: 0.25)
        
        sub2.cancel()
        
        let channelLeftEx = expectation(description: "Channel should have left once")
        let channelRejoinEx = expectation(description: "Channel should not have rejoined")
        channelRejoinEx.isInverted = true
        
        let sub3 = channel.forever { result in
            switch result {
            case .join: channelRejoinEx.fulfill()
            case .leave: channelLeftEx.fulfill()
            default: break
            }
        }
        defer { sub3.cancel() }
        
        channel.leave()
        
        socket.send("disconnect")
        
        waitForExpectations(timeout: 1)
    }
}
