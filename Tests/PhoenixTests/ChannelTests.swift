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
    
    // MARK: constructor

    // https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/channel_test.js#L36
    func testChannelInit() throws {
        let channel = Channel(topic: "rooms:lobby", socket: socket)
        XCTAssert(channel.isClosed)
        XCTAssertEqual(channel.connectionState, "closed")
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
    
    // MARK: updating join params

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
    
    // MARK: join

    // https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/channel_test.js#L105
    func testIsJoiningAfterJoin() throws {
        let channel = Channel(topic: "rooms:lobby", socket: socket)
        channel.join()
        XCTAssertEqual(channel.connectionState, "joining")
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

        channel.push("echo_join_params", callback: self.expectOk(response: params))
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
        let channel = makeChannel(topic: "room:lobby")

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
    
    // https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/channel_test.js#L184
    func testJoinSucceedsIfBeforeTimeout() throws {
        var counter = 0
        let channel = Channel(
            topic: "room:lobby", joinPayloadBlock: { counter += 1; return [:] }, socket: socket
        )
        
        let sub = channel.forever(receiveValue: expect(.join))
        defer { sub.cancel() }
        
        channel.join(timeout: .seconds(2))
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) { self.socket.connect() }
        
        waitForExpectations(timeout: 2)
        
        XCTAssertTrue(channel.isJoined)
        // The joinPush is generated once and sent to the Socket which isn't open, so it's not written.
        // Then a second time after the Socket publishes its open message and the Channel tries to reconnect.
        XCTAssertEqual(2, counter)
    }
    
    // TODO: Fix testJoinRetriesWithBackoffIfTimeout
    // https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/channel_test.js#L206
    func _testJoinRetriesWithBackoffIfTimeout() throws {
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
    
    // https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/channel_test.js#L233
    func testChannelConnectsAfterSocketAndJoinDelay() throws {
        let channel = makeChannel(topic: "room:timeout", payload: ["timeout": 100, "join": true])
        
        var didReceiveError = false
        let didJoinEx = self.expectation(description: "Did join")
        
        let channelSub = channel.forever(receiveValue:
            onResults([
                .error: {
                    // This isn't exactly the same as the JavaScript test. In the JavaScript test,
                    // there is a delay after sending 'connect' before receiving the response.
                    didReceiveError = true; usleep(50_000); self.socket.connect() },
                .join: { didJoinEx.fulfill() },
            ])
        )
        defer { channelSub.cancel() }
        
        channel.join(timeout: .seconds(2))
        
        waitForExpectations(timeout: 2)
        
        XCTAssertTrue(didReceiveError)
        XCTAssertTrue(channel.isJoined)
    }
    
    // https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/channel_test.js#L263
    func testChannelConnectsAfterSocketDelay() throws {
        let channel = makeChannel(topic: "room:lobby")
        
        var didReceiveError = false
        let didJoinEx = self.expectation(description: "Did join")
        
        let channelSub = channel.forever(receiveValue:
            onResults([
                // This isn't exactly the same as the JavaScript test. In the JavaScript test,
                // there is a delay after sending 'connect' before receiving the response.
                .error: { didReceiveError = true; usleep(50_000); self.socket.connect() },
                .join: { didJoinEx.fulfill() },
            ])
        )
        defer { channelSub.cancel() }
        
        channel.join()
        
        waitForExpectations(timeout: 2)
        
        XCTAssertTrue(didReceiveError)
        XCTAssertTrue(channel.isJoined)
    }
    
    // MARK: join push
    
    // https://github.com/phoenixframework/phoenix/blob/496627f2f7bbe92fc481bad81a59dd89d8205508/assets/test/channel_test.js#L333
    // https://github.com/phoenixframework/phoenix/blob/496627f2f7bbe92fc481bad81a59dd89d8205508/assets/test/channel_test.js#L341
    // https://github.com/phoenixframework/phoenix/blob/496627f2f7bbe92fc481bad81a59dd89d8205508/assets/test/channel_test.js#L384
    // https://github.com/phoenixframework/phoenix/blob/496627f2f7bbe92fc481bad81a59dd89d8205508/assets/test/channel_test.js#L384
    // https://github.com/phoenixframework/phoenix/blob/496627f2f7bbe92fc481bad81a59dd89d8205508/assets/test/channel_test.js#L402
    func testSetsChannelStateToJoinedAfterSuccessfulJoin() throws {
        socket.connect()
        
        let channel = makeChannel(topic: "room:lobby")
        
        let sub = channel.forever(receiveValue: expect(.join))
        defer { sub.cancel() }
        
        channel.join()
        
        waitForExpectations(timeout: 2)
        
        XCTAssertTrue(channel.isJoined)
    }
    
    // https://github.com/phoenixframework/phoenix/blob/496627f2f7bbe92fc481bad81a59dd89d8205508/assets/test/channel_test.js#L361
    func testOnlyReceivesSuccessfulCallbackFromSuccessfulJoin() throws {
        let channel = makeChannel(topic: "room:lobby")
        
        let socketSub = socket.autoconnect().forever(receiveValue:
            expectAndThen([.open: { channel.join() }])
        )
        defer { socketSub.cancel() }
        
        let joinEx = self.expectation(description: "Should have joined channel")
        var unexpectedOutputCount = 0
        
        let channelSub = channel.forever { (output: Channel.Output) -> Void in
            switch output {
            case .join: joinEx.fulfill()
            default: unexpectedOutputCount += 1
            }
        }
        defer { channelSub.cancel() }
        
        waitForExpectations(timeout: 2)
        
        waitForTimeout(0.1)
        
        XCTAssertTrue(channel.isJoined)
        XCTAssertEqual(0, unexpectedOutputCount)
    }
    
    // https://github.com/phoenixframework/phoenix/blob/496627f2f7bbe92fc481bad81a59dd89d8205508/assets/test/channel_test.js#L376
    // https://github.com/phoenixframework/phoenix/blob/496627f2f7bbe92fc481bad81a59dd89d8205508/assets/test/channel_test.js#L408
    func testResetsJoinTimerAfterSuccessfulJoin() throws {
        socket.connect()
        
        let channel = makeChannel(topic: "room:lobby")
        
        let sub = channel.forever(receiveValue: expect(.join))
        defer { sub.cancel() }
        
        channel.join()
        
        waitForExpectations(timeout: 2)
        
        XCTAssertTrue(channel.joinTimer.isOff)
    }
    
    // https://github.com/phoenixframework/phoenix/blob/496627f2f7bbe92fc481bad81a59dd89d8205508/assets/test/channel_test.js#L418
    func testSendsAllBufferedMessagesAfterSuccessfulJoin() throws {
        let channel = makeChannel(topic: "room:lobby")
        
        channel.push("echo", payload:["echo": "one"], callback: expectOk(response: ["echo": "one"]))
        channel.push("echo", payload:["echo": "two"], callback: expectOk(response: ["echo": "two"]))
        channel.push("echo", payload:["echo": "three"], callback: expectOk(response: ["echo": "three"]))
        
        let socketSub = socket.forever(receiveValue: onResult(.open, channel.join()))
        defer { socketSub.cancel() }
        
        let channelSub = channel.forever(receiveValue: expect(.join))
        defer { channelSub.cancel() }
        
        socket.connect()
        
        waitForExpectations(timeout: 4)
    }
    
    // MARK: receives timeout
    
    // https://github.com/phoenixframework/phoenix/blob/496627f2f7bbe92fc481bad81a59dd89d8205508/assets/test/channel_test.js#L444
    func testReceivesCorrectErrorAfterJoinTimeout() throws {
        let channel = makeChannel(topic: "room:timeout", payload: ["timeout": 3_000, "join": true])
        
        let timeoutEx = self.expectation(description: "Should have received timeout error")
        let channelSub = channel.forever(receiveValue: { (output: Channel.Output) -> Void in
            guard case Channel.Output.error(Channel.Error.joinTimeout) = output else { return }
            timeoutEx.fulfill()
        })
        defer { channelSub.cancel() }
        
        let socketSub = socket.autoconnect().forever(receiveValue:
            expectAndThen([.open: { channel.join(timeout: .milliseconds(10)) }])
        )
        defer { socketSub.cancel() }
        
        waitForExpectations(timeout: 2)
        
        XCTAssertEqual(channel.connectionState, "errored")
    }
    
    // https://github.com/phoenixframework/phoenix/blob/496627f2f7bbe92fc481bad81a59dd89d8205508/assets/test/channel_test.js#L454
    func testOnlyReceivesTimeoutErrorAfterJoinTimeout() throws {
        let channel = makeChannel(topic: "room:timeout", payload: ["timeout": 3_000, "join": true])
        
        let socketSub = socket.autoconnect().forever(receiveValue:
            expectAndThen([.open: { channel.join(timeout: .milliseconds(10)) }])
        )
        defer { socketSub.cancel() }
        
        let timeoutEx = self.expectation(description: "Should have received timeout error")
        var unexpectedOutputCount = 0
        
        let channelSub = channel.forever { (output: Channel.Output) -> Void in
            switch output {
            case .error(Channel.Error.joinTimeout): timeoutEx.fulfill()
            default: unexpectedOutputCount += 1
            }
        }
        defer { channelSub.cancel() }
        
        waitForExpectations(timeout: 2)
        
        // Give the test a little more time to receive invalid output
        waitForTimeout(0.1)

        XCTAssertEqual(channel.connectionState, "errored")
        XCTAssertEqual(0, unexpectedOutputCount)
    }
    
    // https://github.com/phoenixframework/phoenix/blob/496627f2f7bbe92fc481bad81a59dd89d8205508/assets/test/channel_test.js#L473
    func testSchedulesRejoinTimerAfterJoinTimeout() throws {
        let channel = makeChannel(topic: "room:timeout", payload: ["timeout": 3_000, "join": true])
        channel.rejoinTimeout = { _ in return .seconds(30) }
        
        let timeoutEx = self.expectation(description: "Should have received timeout error")
        let channelSub = channel.forever(receiveValue: { (output: Channel.Output) -> Void in
            guard case Channel.Output.error(Channel.Error.joinTimeout) = output else { return }
            timeoutEx.fulfill()
        })
        defer { channelSub.cancel() }
        
        let socketSub = socket.autoconnect().forever(receiveValue:
            expectAndThen([.open: { channel.join(timeout: .milliseconds(10)) }])
        )
        defer { socketSub.cancel() }
        
        waitForExpectations(timeout: 2)
        
        expectationWithTest(description: "Should have tried to rejoin", test: channel.joinTimer.isRejoinTimer)
        
        waitForExpectations(timeout: 2)
    }
    
    // MARK: receives error
    
    // https://github.com/phoenixframework/phoenix/blob/496627f2f7bbe92fc481bad81a59dd89d8205508/assets/test/channel_test.js#L489
    // https://github.com/phoenixframework/phoenix/blob/496627f2f7bbe92fc481bad81a59dd89d8205508/assets/test/channel_test.js#L501
    // https://github.com/phoenixframework/phoenix/blob/118999e0fd8e8192155b787b4b71e3eb3719e7e5/assets/test/channel_test.js#L603
    func testReceivesErrorAfterJoinError() throws {
        let channel = makeChannel(topic: "room:error", payload: ["error": "boom"])

        let timeoutEx = self.expectation(description: "Should have received error")
        let channelSub = channel.forever(receiveValue: { (output: Channel.Output) -> Void in
            guard case .error(Channel.Error.invalidJoinReply(let reply)) = output else { return }
            XCTAssertEqual(["error": "boom"], reply.response as? [String: String])
            timeoutEx.fulfill()
        })
        defer { channelSub.cancel() }
        
        let socketSub = socket.autoconnect().forever(receiveValue: onResult(.open, channel.join()))
        defer { socketSub.cancel() }
        
        waitForExpectations(timeout: 2)
        
        XCTAssertEqual(channel.connectionState, "errored")
    }
    
    // https://github.com/phoenixframework/phoenix/blob/496627f2f7bbe92fc481bad81a59dd89d8205508/assets/test/channel_test.js#L511
    // https://github.com/phoenixframework/phoenix/blob/118999e0fd8e8192155b787b4b71e3eb3719e7e5/assets/test/channel_test.js#L611
    func testOnlyReceivesErrorResponseAfterJoinError() throws {
        let channel = makeChannel(topic: "room:error", payload: ["error": "boom"])

        let socketSub = socket.autoconnect().forever(receiveValue: onResult(.open, channel.join()))
        defer { socketSub.cancel() }
        
        let errorEx = self.expectation(description: "Should have received error")
        var unexpectedOutputCount = 0
        
        let channelSub = channel.forever { (output: Channel.Output) -> Void in
            switch output {
            case .error(Channel.Error.invalidJoinReply): errorEx.fulfill()
            default: unexpectedOutputCount += 1
            }
        }
        defer { channelSub.cancel() }
        
        waitForExpectations(timeout: 2)
        
        // Give the test a little more time to receive invalid output
        waitForTimeout(0.1)

        XCTAssertEqual(channel.connectionState, "errored")
        XCTAssertEqual(0, unexpectedOutputCount)
    }
    
    // https://github.com/phoenixframework/phoenix/blob/496627f2f7bbe92fc481bad81a59dd89d8205508/assets/test/channel_test.js#L532
    func testClearsTimeoutTimerAfterJoinError() throws {
        let channel = makeChannel(topic: "room:error", payload: ["error": "boom"])

        let timeoutEx = self.expectation(description: "Should have received error")
        let channelSub = channel.forever(receiveValue: { (output: Channel.Output) -> Void in
            guard case .error(Channel.Error.invalidJoinReply) = output else { return }
            timeoutEx.fulfill()
        })
        defer { channelSub.cancel() }
        
        let socketSub = socket.autoconnect().forever(receiveValue: onResult(.open, channel.join()))
        defer { socketSub.cancel() }

        expectationWithTest(
            description: "Should have tried to rejoin",
            test: channel.joinTimer.isRejoinTimer
        )
        waitForExpectations(timeout: 2)

        XCTAssertTrue(channel.joinTimer.isRejoinTimer)
    }
    
    // https://github.com/phoenixframework/phoenix/blob/496627f2f7bbe92fc481bad81a59dd89d8205508/assets/test/channel_test.js#L561
    func testDoesNotSetChannelStateToJoinedAfterJoinError() throws {
        let channel = makeChannel(topic: "room:error", payload: ["error": "boom"])

        let channelSub = channel.forever(receiveValue: expect(.error))
        defer { channelSub.cancel() }
        
        let socketSub = socket.autoconnect().forever(receiveValue: onResult(.open, channel.join()))
        defer { socketSub.cancel() }
        
        waitForExpectations(timeout: 2)
        
        XCTAssertEqual(channel.connectionState, "errored")
    }
    
    // https://github.com/phoenixframework/phoenix/blob/496627f2f7bbe92fc481bad81a59dd89d8205508/assets/test/channel_test.js#L567
    func testDoesNotSendAnyBufferedMessagesAfterJoinError() throws {
        let channel = makeChannel(topic: "room:error", payload: ["error": "boom"])

        var pushed = 0
        let callback: Channel.Callback = { _ in pushed += 1; Swift.print("Callback triggered") }
        channel.push("echo", payload:["echo": "one"], callback: callback)
        channel.push("echo", payload:["echo": "two"], callback: callback)
        channel.push("echo", payload:["echo": "three"], callback: callback)
        
        let socketSub = socket.forever(receiveValue: expectAndThen(.open, channel.join()))
        defer { socketSub.cancel() }
        
        let channelSub = channel.forever(receiveValue: expect(.error))
        defer { channelSub.cancel() }
        
        socket.connect()
        
        waitForExpectations(timeout: 2)
        
        waitForTimeout(0.1)
        
        XCTAssertEqual(0, pushed)
    }

    // MARK: onError

    // https://github.com/phoenixframework/phoenix/blob/118999e0fd8e8192155b787b4b71e3eb3719e7e5/assets/test/channel_test.js#L627
    func testDoesNotRejoinChannelAfterLeaving() {
        socket.reconnectTimeInterval = { _ in .milliseconds(1) }
        let channel = makeChannel(topic: "room:lobby")
        channel.rejoinTimeout = { _ in .milliseconds(5) }

        let channelSub = channel.forever(receiveValue:
            expectAndThen([
                .join: { channel.leave(); self.socket.send("boom") },
            ])
        )
        defer { channelSub.cancel() }

        var didOpen = false
        let socketOpenEx = self.expectation(description: "Should have opened socket")
        socketOpenEx.expectedFulfillmentCount = 2
        socketOpenEx.assertForOverFulfill = false
        let socketSub = socket.autoconnect().forever(receiveValue:
            onResults([
                .open: {
                    socketOpenEx.fulfill()
                    if didOpen == false {
                        didOpen = true
                        channel.join()
                    }
                }
            ])
        )
        defer { socketSub.cancel() }

        waitForExpectations(timeout: 2)

        waitForTimeout(0.2)
    }

    // https://github.com/phoenixframework/phoenix/blob/118999e0fd8e8192155b787b4b71e3eb3719e7e5/assets/test/channel_test.js#L643
    func testDoesNotRejoinChannelAfterClosing() {
        socket.reconnectTimeInterval = { _ in .milliseconds(1) }
        let channel = makeChannel(topic: "room:lobby")
        channel.rejoinTimeout = { _ in .milliseconds(5) }

        let channelSub = channel.forever(receiveValue:
            expectAndThen([
                .join: { channel.leave() },
                .leave: { self.socket.send("boom") }
            ])
        )
        defer { channelSub.cancel() }

        var didOpen = false
        let socketOpenEx = self.expectation(description: "Should have opened socket")
        socketOpenEx.expectedFulfillmentCount = 2
        socketOpenEx.assertForOverFulfill = false
        let socketSub = socket.autoconnect().forever(receiveValue:
            onResults([
                .open: {
                    socketOpenEx.fulfill()
                    if didOpen == false {
                        didOpen = true
                        channel.join()
                    }
                }
            ])
        )
        defer { socketSub.cancel() }

        waitForExpectations(timeout: 2)

        waitForTimeout(0.2)
    }

    // https://github.com/phoenixframework/phoenix/blob/118999e0fd8e8192155b787b4b71e3eb3719e7e5/assets/test/channel_test.js#L659
    func testChannelSendsChannelErrorsToSubscribersAfterJoin() {
        let channel = makeChannel(topic: "room:lobby")

        let callback = expectError(response: ["error": "whatever"])
        let channelSub = channel.forever(receiveValue:
            expectAndThen([
                .join: {
                    channel.push("echo_error", payload: ["error": "whatever"], callback: callback)
                },
                .message: { }
            ])
        )
        defer { channelSub.cancel() }

        let socketSub = socket.autoconnect().forever(receiveValue: onResult(.open, channel.join()))
        defer { socketSub.cancel() }

        waitForExpectations(timeout: 2)
    }

    // MARK: Error

    func testReceivingReplyErrorDoesNotSetChannelStateToErrored() {
        let channel = makeChannel(topic: "room:lobby")

        let callback = expectError(response: ["error": "whatever"])
        let channelSub = channel.forever(receiveValue:
            expectAndThen([
                .join: {
                    channel.push("echo_error", payload: ["error": "whatever"], callback: callback)
                },
            ])
        )
        defer { channelSub.cancel() }

        let socketSub = socket.autoconnect().forever(receiveValue: onResult(.open, channel.join()))
        defer { socketSub.cancel() }

        waitForExpectations(timeout: 2)

        XCTAssertEqual(channel.connectionState, "joined")
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

    func makeChannel(topic: Topic, payload: Payload = [:]) -> Channel {
        let channel = socket.channel(topic, payload: payload)
        channel.rejoinTimeout = { _ in return .seconds(30) }
        return channel
    }
}
