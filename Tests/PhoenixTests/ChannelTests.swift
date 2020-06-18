import XCTest
import Combine
@testable import Phoenix

class ChannelTests: XCTestCase {
    var socket: Socket!
    
    override func setUp() {
        socket = makeSocket()
    }
    
    override func tearDown() {
        socket.disconnect()
        socket = nil
    }

    // https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/channel_test.js#L36
    func testChannelInit() throws {
        let channel = Channel(topic: "rooms:lobby", socket: socket)
        XCTAssert(channel.isClosed)
        XCTAssertEqual(channel.connectionState, "closed")
        XCTAssertFalse(channel.joinedOnce)
        XCTAssertEqual(channel.topic, "rooms:lobby")
        XCTAssertEqual(channel.timeout, Socket.defaultTimeout)
        XCTAssertTrue(channel === channel.joinPush.channel)
    }


    func testChannelInitOverrides() throws {
        let socket = Socket(url: testHelper.defaultURL, timeout: .milliseconds(1234))
        let channel = Channel(topic: "rooms:lobby", joinPayload: ["one": "two"], socket: socket)
        XCTAssertEqual(channel.joinPayload as? [String: String], ["one": "two"])
        XCTAssertEqual(channel.timeout, .milliseconds(1234))
    }

    // https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/channel_test.js#L49
    func testJoinPushPayload() throws {
        let socket = Socket(url: testHelper.defaultURL, timeout: .milliseconds(1234))
        let channel = Channel(topic: "rooms:lobby", joinPayload: ["one": "two"], socket: socket)
        let push = channel.joinPush
        
        XCTAssertEqual(push.payload as? [String: String], ["one": "two"])
        XCTAssertEqual(push.event, .join)
        XCTAssertEqual(push.timeout, .milliseconds(1234))
    }

    // https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/channel_test.js#L59
    // https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/channel_test.js#L76
    func testJoinPushBlockPayload() throws {
        var counter = 1
        let block = { () -> Payload in ["number": counter] }
        let channel = Channel(topic: "rooms:lobby", joinPayloadBlock: block, socket: socket)
        
        XCTAssertEqual(channel.joinPush.payload as? [String: Int], ["number": 1])
        
        counter += 1
        
        // We've made the explicit decision to realize the joinPush.payload when we construct the joinPush struct
        
        XCTAssertEqual(channel.joinPush.payload as? [String: Int], ["number": 2])
    }

    // https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/channel_test.js#L105
    func testIsJoiningAfterJoin() throws {
        let channel = Channel(topic: "rooms:lobby", socket: socket)
        XCTAssertFalse(channel.joinedOnce)
        channel.join()
        XCTAssertEqual(channel.connectionState, "joining")
    }

    // https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/channel_test.js#L111
    func testSetsJoinedOnceToTrue() throws {
        let channel = Channel(topic: "room:lobby", socket: socket)
        XCTAssertFalse(channel.joinedOnce)

        let channelSub = channel.forever(receiveValue: expect(.join))
        defer { channelSub.cancel() }

        let socketSub = socket.autoconnect().forever(receiveValue:
            expectAndThen([.open: { channel.join() }])
        )
        defer { socketSub.cancel() }

        waitForExpectations(timeout: 2)
        XCTAssertTrue(channel.joinedOnce)
    }

    // https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/channel_test.js#L119
    func testJoinTwiceIsNoOp() throws {
        let channel = Channel(topic: "topic", socket: socket)
        channel.join()
        channel.join()
    }

    // https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/channel_test.js#L125
    func testJoinPushParamsMakeItToServer() throws {
        let params = ["did": "make it"]
        let channel = Channel(topic: "room:lobby", joinPayload: params, socket: socket)

        let channelSub = channel.forever(receiveValue: expect(.join))
        defer { channelSub.cancel() }

        let socketSub = socket.autoconnect().forever(receiveValue:
            expectAndThen([.open: { channel.join() }])
        )
        defer { socketSub.cancel() }
        waitForExpectations(timeout: 2)

        channel.push("echo_join_params", callback: self.expect(response: params))
        waitForExpectations(timeout: 2)
    }

    // https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/channel_test.js#L141
    func testJoinCanHaveTimeout() throws {
        let channel = Channel(topic: "topic", socket: socket)
        XCTAssertEqual(channel.joinPush.timeout, Socket.defaultTimeout)
        channel.join(timeout: .milliseconds(1234))
        XCTAssertEqual(channel.joinPush.timeout, .milliseconds(1234))
    }

    // https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/channel_test.js#L152
    func testJoinSameTopicTwiceReturnsSameChannel() throws {
        let channel = socket.channel("room:lobby")

        let channelSub = channel.forever(receiveValue: expect(.join))
        defer { channelSub.cancel() }

        let socketSub = socket.autoconnect().forever(receiveValue:
            expectAndThen([.open: { channel.join() }])
        )
        defer { socketSub.cancel() }
        waitForExpectations(timeout: 2)

        let newChannel = socket.join("room:lobby")
        XCTAssertEqual(channel.topic, newChannel.topic)
        XCTAssertEqual(channel.isJoined, newChannel.isJoined)
        XCTAssertEqual(channel.joinRef, newChannel.joinRef)
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
            socket!.connect()
        }
        
        wait(for: [joinEx], timeout: 2)

        XCTAssert(channel.isJoined)
        XCTAssertEqual(counter, 2)
        // The joinPush is generated once and sent to the Socket which isn't open, so it's not written
        // Then a second time after the Socket publishes it's open message and the Channel tries to reconnect
    }
    
    func testJoinRetriesWithBackoffIfTimeout() throws {
        var counter = 0

        let channel = Channel(
            topic: "room:timeout",
            joinPayloadBlock: {
                counter += 1
                if (counter >= 4) {
                    return ["join": true]
                } else {
                    return ["timeout": 120, "join": true]
                }
            },
            socket: socket
        )
        channel.rejoinTimeout = { attempt in
            switch attempt {
            case 0: XCTFail("Rejoin timeouts start at 1"); return .seconds(1)
            case 1, 2, 3, 4: return .milliseconds(10 * attempt)
            default: return .seconds(2)
            }
        }

        let socketSub = socket.forever(receiveValue:
            expectAndThen([.open: { channel.join(timeout: .milliseconds(100)) }])
        )
        defer { socketSub.cancel() }

        let channelSub = channel.forever(receiveValue:
            expectAndThen([
                .join: { XCTAssertEqual(4, counter)  }
                // 1st is the first backoff amount of 10 milliseconds
                // 2nd is the second backoff amount of 20 milliseconds
                // 3rd is the third backoff amount of 30 milliseconds
                // 4th is the successful join, where we don't ask the server to sleep
            ])
        )
        defer { channelSub.cancel() }

        socket.connect()

        waitForExpectations(timeout: 4)
    }
    
    func testSetsStateToErroredAfterJoinTimeout() throws {
        defer { socket.disconnect() }
        
        let openEx = expectation(description: "Socket should have opened")
        
        let sub = socket.forever {
            if case .open = $0 { openEx.fulfill() }
        }
        defer { sub.cancel() }
        
        socket.connect()
        
        wait(for: [openEx], timeout: 1)
        
        // Very large timeout for the server to wait before erroring
        let channel = Channel(topic: "room:timeout", joinPayload: ["timeout": 3_000, "join": true], socket: socket)
        
        let erroredEx = expectation(description: "Channel should not have joined")
        
        let sub2 = channel.forever {
            if case .error = $0 {
                erroredEx.fulfill()
            }
        }
        defer { sub2.cancel() }
        
        // Very short timeout for the joinPush
        channel.join(timeout: .milliseconds(100))
        
        wait(for: [erroredEx], timeout: 1)
        
        XCTAssertEqual(channel.connectionState, "errored")
    }
    
    // MARK: old tests before https://github.com/shareup/phoenix-apple/pull/4
    
    func testJoinAndLeaveEvents() throws {
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
        
        waitForExpectations(timeout: 1)
    }
    
    func testPushCallback() throws {
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
    
    func testReceiveMessages() throws {
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
    
    func testMultipleSocketsCollaborating() throws {
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
    
    func testRejoinsAfterDisconnect() throws {
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

extension ChannelTests {
    func makeSocket() -> Socket {
        let socket = Socket(url: testHelper.defaultURL)
        // We don't want the socket to reconnect unless the test requires it to.
        socket.reconnectTimeInterval = { _ in .seconds(30) }
        return socket
    }
}
