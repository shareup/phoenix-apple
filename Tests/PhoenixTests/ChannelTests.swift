import Combine
@testable import Phoenix
import XCTest

class ChannelTests: XCTestCase {
    var socket: Socket!

    override func setUpWithError() throws {
        try super.setUpWithError()
        socket = makeSocket()
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()
        socket.disconnectAndWait()
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

        let channelSub = channel.sink(receiveValue: expect(.join))
        defer { channelSub.cancel() }

        let socketSub = socket.autoconnect().sink(
            receiveValue:
            expectAndThen([.open: { channel.join() }])
        )
        defer { socketSub.cancel() }
        waitForExpectations(timeout: 2)

        channel.push("echo_join_params", callback: expectOk(response: params))
        waitForExpectations(timeout: 2)
    }

    func testJoinReplyIsSentToChannel() throws {
        let ex = expectation(description: "Did receive join reply")

        let channel = Channel(topic: "room:lobby", socket: socket)
        let channelSub = channel.sink { msg in
            switch msg {
            case let .join(reply):
                guard let response = reply.payload["response"] as? [String: String] else {
                    return XCTFail()
                }
                XCTAssertEqual("You're absolutely wonderful!", response["message"])
                ex.fulfill()
            default:
                break
            }
        }
        defer { channelSub.cancel() }

        let socketSub = socket
            .autoconnect()
            .sink(receiveValue: expectAndThen([.open: { channel.join() }]))
        defer { socketSub.cancel() }

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

        let channelSub = channel.sink(receiveValue: expect(.join))
        defer { channelSub.cancel() }

        let socketSub = socket.autoconnect().sink(
            receiveValue:
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

        let sub = channel.sink(receiveValue: expect(.join))
        defer { sub.cancel() }

        channel.join(timeout: .seconds(2))
        DispatchQueue.main
            .asyncAfter(deadline: .now() + .milliseconds(100)) { self.socket.connect() }

        waitForExpectations(timeout: 2)

        XCTAssertTrue(channel.isJoined)
        // The joinPush is generated once and sent to the Socket which isn't open, so it's not written.
        // Then a second time after the Socket publishes its open message and the Channel tries to reconnect.
        XCTAssertEqual(2, counter)
    }

    // TODO: This test doesn't really do what we want it to. The original join message should
    // timeout, but, in the meantime, a leave message should be sent and (?) its reply received
    // back. Then, at some point (either before or after the leave reply is received), another
    // join message should be sent and the reply received, resulting the channel actually
    // being joined. The problem is the Elixir server is just sleeping after it gets the
    // original join message, which means it can't process the leave or second join message
    // until the initial sleep finishes. Replacing the Phoenix server with a more custom one
    // should fix this.
    //
    // https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/channel_test.js#L206
    func testJoinRetriesWithBackoffIfTimeout() throws {
        var counter = 0

        let startTime = Date()

        var channel: Channel?
        channel = Channel(
            topic: "room:timeout",
            joinPayloadBlock: {
                defer { counter += 1 }
                let time = startTime
                    .timeIntervalSinceNow * -1000 // Convert to positive milliseconds

                switch counter {
                case 0:
                    return ["timeout": 2000, "join": true]
                case 1:
                    XCTAssertGreaterThanOrEqual(time, 100)
                    return ["timeout": 0, "join": true]
                case 2:
                    XCTAssertGreaterThanOrEqual(time, 4000)
                    return ["timeout": 0, "join": true]
                default:
                    return ["timeout": 0, "join": true]
                }
            },
            socket: socket
        )
        channel!.rejoinTimeout = { attempt in
            switch attempt {
            case 0: XCTFail("Rejoin timeouts start at 1"); return .seconds(1)
            case 1: return .milliseconds(100)
            case 2: return .seconds(4)
            default: return .seconds(10)
            }
        }

        let socketSub = socket.sink(
            receiveValue:
            expectAndThen([.open: { channel!.join(timeout: .milliseconds(20)) }])
        )
        defer { socketSub.cancel() }

        let joinEx = expectation(description: "Did join after backoff")
        joinEx.assertForOverFulfill = false
        let channelSub = channel!.sink { message in
            guard case .join = message else { return }
            joinEx.fulfill()
        }
        defer { channelSub.cancel() }

        socket.connect()

        waitForExpectations(timeout: 10)
    }

    // https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/channel_test.js#L233
    func testChannelConnectsAfterSocketAndJoinDelay() throws {
        let channel = makeChannel(
            topic: "room:timeout",
            payload: ["timeout": 100, "join": true]
        )

        var didReceiveError = false
        let didJoinEx = expectation(description: "Did join")

        let channelSub = channel.sink(
            receiveValue:
            onResults([
                .error: {
                    // This isn't exactly the same as the JavaScript test. In the JavaScript test,
                    // there is a delay after sending 'connect' before receiving the response.
                    didReceiveError = true
                    usleep(50000)
                    self.socket.connect()
                },
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
        let didJoinEx = expectation(description: "Did join")

        let channelSub = channel.sink(
            receiveValue:
            onResults([
                // This isn't exactly the same as the JavaScript test. In the JavaScript test,
                // there is a delay after sending 'connect' before receiving the response.
                .error: {
                    didReceiveError = true
                    usleep(50000)
                    self.socket.connect()
                },
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

        let sub = channel.sink(receiveValue: expect(.join))
        defer { sub.cancel() }

        channel.join()

        waitForExpectations(timeout: 2)

        XCTAssertTrue(channel.isJoined)
    }

    // https://github.com/phoenixframework/phoenix/blob/496627f2f7bbe92fc481bad81a59dd89d8205508/assets/test/channel_test.js#L361
    func testOnlyReceivesSuccessfulCallbackFromSuccessfulJoin() throws {
        let channel = makeChannel(topic: "room:lobby")

        let socketSub = socket.autoconnect().sink(
            receiveValue:
            expectAndThen([.open: { channel.join() }])
        )
        defer { socketSub.cancel() }

        let joinEx = expectation(description: "Should have joined channel")
        var unexpectedOutputCount = 0

        let channelSub = channel.sink { (output: Channel.Output) in
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

        let sub = channel.sink(receiveValue: expect(.join))
        defer { sub.cancel() }

        channel.join()

        waitForExpectations(timeout: 2)

        XCTAssertTrue(channel.joinTimer.isOff)
    }

    // https://github.com/phoenixframework/phoenix/blob/496627f2f7bbe92fc481bad81a59dd89d8205508/assets/test/channel_test.js#L418
    func testSendsAllBufferedMessagesAfterSuccessfulJoin() throws {
        let channel = makeChannel(topic: "room:lobby")

        channel.push(
            "echo",
            payload: ["echo": "one"],
            callback: expectOk(response: ["echo": "one"])
        )
        channel.push(
            "echo",
            payload: ["echo": "two"],
            callback: expectOk(response: ["echo": "two"])
        )
        channel.push(
            "echo",
            payload: ["echo": "three"],
            callback: expectOk(response: ["echo": "three"])
        )

        let socketSub = socket.sink(receiveValue: onResult(.open, channel.join()))
        defer { socketSub.cancel() }

        let channelSub = channel.sink(receiveValue: expect(.join))
        defer { channelSub.cancel() }

        socket.connect()

        waitForExpectations(timeout: 4)
    }

    // MARK: receives timeout

    // https://github.com/phoenixframework/phoenix/blob/496627f2f7bbe92fc481bad81a59dd89d8205508/assets/test/channel_test.js#L444
    func testReceivesCorrectErrorAfterJoinTimeout() throws {
        let channel = makeChannel(
            topic: "room:timeout",
            payload: ["timeout": 3000, "join": true]
        )

        let timeoutEx = expectation(description: "Should have received timeout error")
        let channelSub = channel.sink(receiveValue: { (output: Channel.Output) in
            guard case Channel.Output.error(Channel.Error.joinTimeout) = output else { return }
            timeoutEx.fulfill()
        })
        defer { channelSub.cancel() }

        let socketSub = socket.autoconnect().sink(
            receiveValue:
            expectAndThen([.open: { channel.join(timeout: .milliseconds(10)) }])
        )
        defer { socketSub.cancel() }

        waitForExpectations(timeout: 2)

        XCTAssertEqual(channel.connectionState, "errored")
    }

    // https://github.com/phoenixframework/phoenix/blob/496627f2f7bbe92fc481bad81a59dd89d8205508/assets/test/channel_test.js#L454
    func testOnlyReceivesTimeoutErrorAfterJoinTimeout() throws {
        let channel = makeChannel(
            topic: "room:timeout",
            payload: ["timeout": 3000, "join": true]
        )

        let socketSub = socket.autoconnect().sink(
            receiveValue:
            expectAndThen([.open: { channel.join(timeout: .milliseconds(10)) }])
        )
        defer { socketSub.cancel() }

        let timeoutEx = expectation(description: "Should have received timeout error")
        var unexpectedOutputCount = 0

        let channelSub = channel.sink { (output: Channel.Output) in
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
        let channel = makeChannel(
            topic: "room:timeout",
            payload: ["timeout": 3000, "join": true]
        )
        channel.rejoinTimeout = { _ in .seconds(30) }

        let timeoutEx = expectation(description: "Should have received timeout error")
        let channelSub = channel.sink(receiveValue: { (output: Channel.Output) in
            guard case Channel.Output.error(Channel.Error.joinTimeout) = output else { return }
            timeoutEx.fulfill()
        })
        defer { channelSub.cancel() }

        let socketSub = socket.autoconnect().sink(
            receiveValue:
            expectAndThen([.open: { channel.join(timeout: .milliseconds(10)) }])
        )
        defer { socketSub.cancel() }

        waitForExpectations(timeout: 2)

        expectationWithTest(
            description: "Should have tried to rejoin",
            test: channel.joinTimer.isRejoinTimer
        )

        waitForExpectations(timeout: 2)
    }

    // MARK: receives error

    // https://github.com/phoenixframework/phoenix/blob/496627f2f7bbe92fc481bad81a59dd89d8205508/assets/test/channel_test.js#L489
    // https://github.com/phoenixframework/phoenix/blob/496627f2f7bbe92fc481bad81a59dd89d8205508/assets/test/channel_test.js#L501
    // https://github.com/phoenixframework/phoenix/blob/118999e0fd8e8192155b787b4b71e3eb3719e7e5/assets/test/channel_test.js#L603
    func testReceivesErrorAfterJoinError() throws {
        let channel = makeChannel(topic: "room:error", payload: ["error": "boom"])

        let timeoutEx = expectation(description: "Should have received error")
        let channelSub = channel.sink(receiveValue: { (output: Channel.Output) in
            guard case let .error(Channel.Error.invalidJoinReply(reply)) = output
            else { return }
            XCTAssertEqual(["error": "boom"], reply.response as? [String: String])
            timeoutEx.fulfill()
        })
        defer { channelSub.cancel() }

        let socketSub = socket.autoconnect().sink(receiveValue: onResult(.open, channel.join()))
        defer { socketSub.cancel() }

        waitForExpectations(timeout: 2)

        XCTAssertEqual(channel.connectionState, "errored")
    }

    // https://github.com/phoenixframework/phoenix/blob/496627f2f7bbe92fc481bad81a59dd89d8205508/assets/test/channel_test.js#L511
    // https://github.com/phoenixframework/phoenix/blob/118999e0fd8e8192155b787b4b71e3eb3719e7e5/assets/test/channel_test.js#L611
    func testOnlyReceivesErrorResponseAfterJoinError() throws {
        let channel = makeChannel(topic: "room:error", payload: ["error": "boom"])

        let socketSub = socket.autoconnect().sink(receiveValue: onResult(.open, channel.join()))
        defer { socketSub.cancel() }

        let errorEx = expectation(description: "Should have received error")
        var unexpectedOutputCount = 0

        let channelSub = channel.sink { (output: Channel.Output) in
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

        let timeoutEx = expectation(description: "Should have received error")
        let channelSub = channel.sink(receiveValue: { (output: Channel.Output) in
            guard case .error(Channel.Error.invalidJoinReply) = output else { return }
            timeoutEx.fulfill()
        })
        defer { channelSub.cancel() }

        let socketSub = socket.autoconnect().sink(receiveValue: onResult(.open, channel.join()))
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

        let channelSub = channel.sink(receiveValue: expect(.error))
        defer { channelSub.cancel() }

        let socketSub = socket.autoconnect().sink(receiveValue: onResult(.open, channel.join()))
        defer { socketSub.cancel() }

        waitForExpectations(timeout: 2)

        XCTAssertEqual(channel.connectionState, "errored")
    }

    // https://github.com/phoenixframework/phoenix/blob/496627f2f7bbe92fc481bad81a59dd89d8205508/assets/test/channel_test.js#L567
    func testDoesNotSendAnyBufferedMessagesAfterJoinError() throws {
        let channel = makeChannel(topic: "room:error", payload: ["error": "boom"])

        var pushed = 0
        let callback: Channel.Callback = { _ in pushed += 1 }
        channel.push("echo", payload: ["echo": "one"], callback: callback)
        channel.push("echo", payload: ["echo": "two"], callback: callback)
        channel.push("echo", payload: ["echo": "three"], callback: callback)

        let socketSub = socket.sink(receiveValue: expectAndThen(.open, channel.join()))
        defer { socketSub.cancel() }

        let channelSub = channel.sink(receiveValue: expect(.error))
        defer { channelSub.cancel() }

        socket.connect()

        waitForExpectations(timeout: 2)

        waitForTimeout(0.1)

        XCTAssertEqual(0, pushed)
    }

    // MARK: onError

    // https://github.com/phoenixframework/phoenix/blob/118999e0fd8e8192155b787b4b71e3eb3719e7e5/assets/test/channel_test.js#L627
    func testDoesNotRejoinChannelAfterLeaving() throws {
        socket.reconnectTimeInterval = { _ in .milliseconds(1) }
        let channel = makeChannel(topic: "room:lobby")
        channel.rejoinTimeout = { _ in .milliseconds(5) }

        let channelSub = channel.sink(
            receiveValue:
            expectAndThen([
                .join: { channel.leave(); self.socket.send("boom") },
            ])
        )
        defer { channelSub.cancel() }

        var didOpen = false
        let socketOpenEx = expectation(description: "Should have opened socket")
        socketOpenEx.expectedFulfillmentCount = 2
        socketOpenEx.assertForOverFulfill = false
        let socketSub = socket.autoconnect().sink(
            receiveValue:
            onResults([
                .open: {
                    socketOpenEx.fulfill()
                    if didOpen == false {
                        didOpen = true
                        channel.join()
                    }
                },
            ])
        )
        defer { socketSub.cancel() }

        waitForExpectations(timeout: 2)

        waitForTimeout(0.2)
    }

    // https://github.com/phoenixframework/phoenix/blob/118999e0fd8e8192155b787b4b71e3eb3719e7e5/assets/test/channel_test.js#L643
    func testDoesNotRejoinChannelAfterClosing() throws {
        socket.reconnectTimeInterval = { _ in .milliseconds(1) }
        let channel = makeChannel(topic: "room:lobby")
        channel.rejoinTimeout = { _ in .milliseconds(5) }

        let channelSub = channel.sink(
            receiveValue:
            expectAndThen([
                .join: { channel.leave() },
                .leave: { self.socket.send("boom") },
            ])
        )
        defer { channelSub.cancel() }

        var didOpen = false
        let socketOpenEx = expectation(description: "Should have opened socket")
        socketOpenEx.expectedFulfillmentCount = 2
        socketOpenEx.assertForOverFulfill = false
        let socketSub = socket.autoconnect().sink(
            receiveValue:
            onResults([
                .open: {
                    socketOpenEx.fulfill()
                    if didOpen == false {
                        didOpen = true
                        channel.join()
                    }
                },
            ])
        )
        defer { socketSub.cancel() }

        waitForExpectations(timeout: 2)

        waitForTimeout(0.2)
    }

    // https://github.com/phoenixframework/phoenix/blob/118999e0fd8e8192155b787b4b71e3eb3719e7e5/assets/test/channel_test.js#L659
    func testChannelSendsChannelErrorsToSubscribersAfterJoin() throws {
        let channel = makeChannel(topic: "room:lobby")

        let callback = expectError(response: ["error": "whatever"])
        let channelSub = channel.sink(
            receiveValue:
            expectAndThen([
                .join: {
                    channel.push(
                        "echo_error",
                        payload: ["error": "whatever"],
                        callback: callback
                    )
                },
            ])
        )
        defer { channelSub.cancel() }

        let socketSub = socket.autoconnect().sink(receiveValue: onResult(.open, channel.join()))
        defer { socketSub.cancel() }

        waitForExpectations(timeout: 2)
    }

    // MARK: onClose

    // https://github.com/phoenixframework/phoenix/blob/118999e0fd8e8192155b787b4b71e3eb3719e7e5/assets/test/channel_test.js#L694
    // https://github.com/phoenixframework/phoenix/blob/118999e0fd8e8192155b787b4b71e3eb3719e7e5/assets/test/channel_test.js#L714
    func testClosingChannelSetsStateToClosed() throws {
        let channel = makeChannel(topic: "room:lobby")

        let callback = expectOk(response: ["close": "whatever"])
        let channelSub = channel.sink(
            receiveCompletion: expectFinished(),
            receiveValue: expectAndThen([
                .join: {
                    channel.push(
                        "echo_close",
                        payload: ["close": "whatever"],
                        callback: callback
                    )
                },
                .leave: {},
            ])
        )
        defer { channelSub.cancel() }

        let socketSub = socket.autoconnect().sink(receiveValue: onResult(.open, channel.join()))
        defer { socketSub.cancel() }

        waitForExpectations(timeout: 2)

        XCTAssertEqual(channel.connectionState, "closed")
    }

    // https://github.com/phoenixframework/phoenix/blob/118999e0fd8e8192155b787b4b71e3eb3719e7e5/assets/test/channel_test.js#L702
    func testChannelDoesNotRejoinAfterClosing() throws {
        let channel = makeChannel(topic: "room:lobby")
        channel.rejoinTimeout = { _ in .milliseconds(10) }

        let callback = expectOk(response: ["close": "whatever"])
        let channelSub = channel.sink(
            receiveCompletion: expectFinished(),
            receiveValue: expectAndThen([
                .join: {
                    channel.push(
                        "echo_close",
                        payload: ["close": "whatever"],
                        callback: callback
                    )
                },
                .leave: {},
            ])
        )
        defer { channelSub.cancel() }

        let socketSub = socket.autoconnect().sink(receiveValue: onResult(.open, channel.join()))
        defer { socketSub.cancel() }

        waitForExpectations(timeout: 2)

        XCTAssertEqual(channel.connectionState, "closed")

        // Wait to see if the channel tries to reconnect
        waitForTimeout(0.1)
    }

    // https://github.com/phoenixframework/phoenix/blob/118999e0fd8e8192155b787b4b71e3eb3719e7e5/assets/test/channel_test.js#L725
    func testChannelIsRemovedFromSocketsListOfChannelsAfterClose() throws {
        let channel = makeChannel(topic: "room:lobby")
        channel.rejoinTimeout = { _ in .milliseconds(10) }

        let callback = expectOk(response: ["close": "whatever"])
        let channelSub = channel.sink(
            receiveCompletion: expectFinished(),
            receiveValue: expectAndThen([
                .join: {
                    channel.push(
                        "echo_close",
                        payload: ["close": "whatever"],
                        callback: callback
                    )
                },
                .leave: {},
            ])
        )
        defer { channelSub.cancel() }

        let socketSub = socket.autoconnect().sink(receiveValue: onResult(.open, channel.join()))
        defer { socketSub.cancel() }

        waitForExpectations(timeout: 2)

        XCTAssertTrue(socket.joinedChannels.isEmpty)
    }

    // MARK: onMessage

    // https://github.com/phoenixframework/phoenix/blob/118999e0fd8e8192155b787b4b71e3eb3719e7e5/assets/test/channel_test.js#L742
    func testIncomingMessageIncludesPayload() throws {
        let channel = makeChannel(topic: "room:lobby")

        channel.push(
            "echo",
            payload: ["echo": "one"],
            callback: expectOk(response: ["echo": "one"])
        )

        let socketSub = socket.sink(receiveValue: onResult(.open, channel.join()))
        defer { socketSub.cancel() }

        let channelSub = channel.sink(receiveValue: expect(.join))
        defer { channelSub.cancel() }

        socket.connect()

        waitForExpectations(timeout: 2)
    }

    // MARK: canPush

    // https://github.com/phoenixframework/phoenix/blob/118999e0fd8e8192155b787b4b71e3eb3719e7e5/assets/test/channel_test.js#L757
    func testCanPushIsTrueWhenSocketAndChannelAreConnected() throws {
        let channel = makeChannel(topic: "room:lobby")

        let socketSub = socket.sink(receiveValue: onResult(.open, channel.join()))
        defer { socketSub.cancel() }

        let channelSub = channel.sink(receiveValue: expect(.join))
        defer { channelSub.cancel() }

        socket.connect()

        waitForExpectations(timeout: 2)

        XCTAssertTrue(channel.canPush)
    }

    // https://github.com/phoenixframework/phoenix/blob/118999e0fd8e8192155b787b4b71e3eb3719e7e5/assets/test/channel_test.js#L764
    func testCanPushIsFalseWhenSocketIsDisconnectedOrChannelIsNotJoined() throws {
        let channel = makeChannel(topic: "room:lobby")
        XCTAssertFalse(channel.canPush)

        let socketSub = socket.sink(
            receiveValue:
            expectAndThen([
                .open: {
                    XCTAssertFalse(channel.canPush)
                    channel.join()
                },
            ])
        )
        defer { socketSub.cancel() }

        let channelSub = channel.sink(receiveValue: expect(.join))
        defer { channelSub.cancel() }

        socket.connect()

        waitForExpectations(timeout: 2)

        XCTAssertTrue(channel.canPush)
    }

    // MARK: on

    // https://github.com/phoenixframework/phoenix/blob/118999e0fd8e8192155b787b4b71e3eb3719e7e5/assets/test/channel_test.js#L792
    func testCallsCallbackButDoesNotNotifySubscriberForReply() throws {
        let channel = makeChannel(topic: "room:lobby")

        let replyEx = expectation(description: "Should have received reply")
        channel.push("echo", payload: ["echo": "hello"])
            { (result: Result<Channel.Reply, Swift.Error>) in
                guard case let .success(reply) = result else { return XCTFail() }
                XCTAssertTrue(reply.isOk)
                XCTAssertEqual("hello", reply.response["echo"] as? String)
                replyEx.fulfill()
            }

        let socketSub = socket.sink(receiveValue: onResult(.open, channel.join()))
        defer { socketSub.cancel() }

        let messageEx = expectation(description: "Should not have received message")
        messageEx.isInverted = true
        let channelSub = channel.sink { output in
            switch output {
            case .message:
                messageEx.fulfill()
            default: break
            }
        }
        defer { channelSub.cancel() }

        socket.connect()

        wait(for: [replyEx], timeout: 2)
        wait(for: [messageEx], timeout: 0.1)
    }

    // https://github.com/phoenixframework/phoenix/blob/118999e0fd8e8192155b787b4b71e3eb3719e7e5/assets/test/channel_test.js#L805
    func testDoesNotCallCallbackForOtherMessages() throws {
        let channel = makeChannel(topic: "room:lobby")

        let callbackEx = expectation(description: "Should only call callback for its event")
        channel.push("echo") { (result: Result<Channel.Reply, Error>) in
            callbackEx.fulfill()
            guard case let .success(reply) = result else { return XCTFail() }
            XCTAssertTrue(reply.isOk)
            XCTAssertEqual("phx_reply", reply.message.event)
        }
        channel.push(
            "echo",
            payload: ["echo": "one"],
            callback: expectOk(response: ["echo": "one"])
        )

        let socketSub = socket.sink(receiveValue: onResult(.open, channel.join()))
        defer { socketSub.cancel() }

        let channelSub = channel.sink(receiveValue: expect(.join))
        defer { channelSub.cancel() }

        socket.connect()

        waitForExpectations(timeout: 2)
    }

    // https://github.com/phoenixframework/phoenix/blob/118999e0fd8e8192155b787b4b71e3eb3719e7e5/assets/test/channel_test.js#L820
    func testChannelGeneratesUniqueRefsForEachEvent() throws {
        let channel = makeChannel(topic: "room:lobby")

        var refs = Set<Ref>()
        let callbackEx = expectation(description: "Should have called two callbacks")
        callbackEx.expectedFulfillmentCount = 2
        let callback = { (result: Result<Channel.Reply, Error>) in
            guard case let .success(reply) = result else { return }
            DispatchQueue.main.sync { _ = refs.insert(reply.ref) }
            callbackEx.fulfill()
        }

        channel.push("echo", callback: callback)
        channel.push("echo", callback: callback)

        let socketSub = socket.sink(receiveValue: onResult(.open, channel.join()))
        defer { socketSub.cancel() }

        let channelSub = channel.sink(receiveValue: expect(.join))
        defer { channelSub.cancel() }

        socket.connect()

        waitForExpectations(timeout: 2)

        XCTAssertEqual(2, refs.count)
    }

    // MARK: off

    // https://github.com/phoenixframework/phoenix/blob/118999e0fd8e8192155b787b4b71e3eb3719e7e5/assets/test/channel_test.js#L848
    func testRemovingSubscriberBeforeEventIsPushedPreventsNotification() throws {
        let channel = makeChannel(topic: "room:lobby")

        let pushCallbackEx = expectation(description: "Should have received callback")
        channel.push("echo") { _ in pushCallbackEx.fulfill() }

        let messageEx = expectation(description: "Should not have received message")
        messageEx.isInverted = true
        let channelSub = channel.sink { _ in messageEx.fulfill() }

        let joinEx = expectation(description: "Should have joined socket")
        let socketSub = socket.sink(
            receiveValue:
            onResults([
                .open: {
                    channelSub.cancel()
                    channel.join()
                    joinEx.fulfill()
                },
            ])
        )
        defer { socketSub.cancel() }

        socket.connect()

        wait(for: [joinEx, pushCallbackEx], timeout: 2, enforceOrder: true)
        wait(for: [messageEx], timeout: 0.2)
    }

    // MARK: Push

    // https://github.com/phoenixframework/phoenix/blob/118999e0fd8e8192155b787b4b71e3eb3719e7e5/assets/test/channel_test.js#L911
    func testSendsPushEventAfterJoiningChannel() throws {
        let channel = makeChannel(topic: "room:lobby")

        let socketSub = socket.sink(receiveValue: onResult(.open, channel.join()))
        defer { socketSub.cancel() }

        let pushEx = expectation(description: "Should have received push reply")
        let channelSub = channel.sink(
            receiveValue:
            expectAndThen([
                .join: {
                    channel.push("echo", payload: ["echo": "word"]) { result in
                        guard case let .success(reply) = result else { return }
                        guard reply.isOk else { return }
                        XCTAssertEqual(["echo": "word"], reply.response as? [String: String])
                        pushEx.fulfill()
                    }
                },
            ])
        )
        defer { channelSub.cancel() }

        socket.connect()

        waitForExpectations(timeout: 2)
    }

    // https://github.com/phoenixframework/phoenix/blob/118999e0fd8e8192155b787b4b71e3eb3719e7e5/assets/test/channel_test.js#L918
    func testEnqueuesPushEventToBeSentWhenChannelIsJoined() throws {
        let channel = makeChannel(topic: "room:lobby")

        var didReceiveJoin = false
        let noPushEx = expectation(description: "Should have wait to send push after joining")
        noPushEx.isInverted = true
        let pushEx = expectation(description: "Should have sent push after joining")

        channel.push("echo") { _ in
            DispatchQueue.main.async {
                if didReceiveJoin == false {
                    noPushEx.fulfill()
                }
                pushEx.fulfill()
            }
        }

        let socketSub = socket.sink(receiveValue: onResult(.open, channel.join()))
        defer { socketSub.cancel() }

        let channelSub = channel
            .receive(on: DispatchQueue.main)
            .sink(receiveValue: expectAndThen([.join: { didReceiveJoin = true }]))
        defer { channelSub.cancel() }

        socket.connect()

        wait(for: [noPushEx], timeout: 0.2)
        waitForExpectations(timeout: 2)
    }

    // https://github.com/phoenixframework/phoenix/blob/118999e0fd8e8192155b787b4b71e3eb3719e7e5/assets/test/channel_test.js#L930
    func testDoesNotPushIfChannelJoinTimesOut() throws {
        let channel = makeChannel(
            topic: "room:timeout",
            payload: ["timeout": 500, "join": true]
        )

        let noPushEx = expectation(description: "Should not have sent push")
        noPushEx.isInverted = true
        channel.push("echo") { _ in noPushEx.fulfill() }

        let connectEx = expectation(description: "Should have connected to socket")
        let socketSub = socket.sink { output in
            guard case .open = output else { return }
            channel.join(timeout: .milliseconds(50))
            connectEx.fulfill()
        }
        defer { socketSub.cancel() }

        socket.connect()

        wait(for: [connectEx], timeout: 2)
        wait(for: [noPushEx], timeout: 0.1)
    }

    // https://github.com/phoenixframework/phoenix/blob/118999e0fd8e8192155b787b4b71e3eb3719e7e5/assets/test/channel_test.js#L942
    func testPushesUseChannelTimeoutByDefault() throws {
        let channel: Channel = makeChannel(topic: "room:lobby")
        let channelTimeout = channel.timeout

        channel.push("echo")

        XCTAssertEqual(channelTimeout, channel.pending[0].timeout)
        channel.leave()
    }

    // https://github.com/phoenixframework/phoenix/blob/118999e0fd8e8192155b787b4b71e3eb3719e7e5/assets/test/channel_test.js#L956
    func testPushesCanAcceptCustomTimeout() throws {
        let channel = makeChannel(topic: "room:lobby")
        let channelTimeout = channel.timeout

        let customTimeout = DispatchTimeInterval.microseconds(1)
        channel.push("echo", payload: [:], timeout: customTimeout, callback: { _ in })

        let push = channel.pending[0]
        XCTAssertNotEqual(channelTimeout, push.timeout)
        XCTAssertEqual(customTimeout, push.timeout)
    }

    // https://github.com/phoenixframework/phoenix/blob/118999e0fd8e8192155b787b4b71e3eb3719e7e5/assets/test/channel_test.js#L956
    func testPushesTimeoutAfterCustomTimeout() throws {
        let channel = makeChannel(topic: "room:lobby")

        channel.push(
            "echo_timeout",
            payload: ["echo": "word", "timeout": 2000],
            timeout: .milliseconds(20),
            callback: expectFailure(.pushTimeout)
        )
        XCTAssertEqual(1, channel.pending.count)

        let socketSub = socket.sink(receiveValue: expectAndThen(.open, channel.join()))
        defer { socketSub.cancel() }

        socket.connect()

        waitForExpectations(timeout: 2)

        XCTAssertTrue(channel.inFlight.isEmpty)
        XCTAssertTrue(channel.pending.isEmpty)
    }

    func testShortPushTimeoutsAreCalledAfterLongPushTimeoutsHaveBeenScheduled() throws {
        let channel = makeChannel(topic: "room:lobby")

        func payload(_ timeout: Int) -> [String: Any] { ["echo": "word", "timeout": timeout] }
        let shortTimeoutCallback = expectFailure(.pushTimeout)

        let socketSub = socket.sink(receiveValue: expectAndThen(.open, channel.join()))
        defer { socketSub.cancel() }

        func pushShortTimeoutAfterFirstPushIsInFlight() {
            // Make sure the first push is in flight before adding the second one
            DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(50)) {
                XCTAssertEqual(1, channel.inFlight.count)
                channel.push(
                    "echo_timeout",
                    payload: payload(100),
                    timeout: .milliseconds(50),
                    callback: shortTimeoutCallback
                )
            }
        }

        let channelSub = channel.sink(
            receiveValue:
            expectAndThen([
                .join: {
                    channel.push(
                        "echo_timeout",
                        payload: payload(2000),
                        timeout: .seconds(2),
                        callback: { _ in }
                    )
                    pushShortTimeoutAfterFirstPushIsInFlight()
                },
            ])
        )
        defer { channelSub.cancel() }

        socket.connect()

        waitForExpectations(timeout: 2)
    }

    // https://github.com/phoenixframework/phoenix/blob/118999e0fd8e8192155b787b4b71e3eb3719e7e5/assets/test/channel_test.js#L970
    func testPushDoesNotTimeoutAfterReceivingReply() throws {
        let channel = makeChannel(topic: "room:lobby")

        let okEx = expectation(description: "Should have received 'ok'")
        let timeoutEx = expectation(description: "Should not have received a timeout")
        timeoutEx.isInverted = true
        channel
            .push(
                "echo",
                payload: [:],
                timeout: .milliseconds(100)
            ) { (result: Result<Channel.Reply, Swift.Error>) in
                switch result {
                case let .success(reply) where reply.isOk:
                    okEx.fulfill()
                case .failure(Channel.Error.pushTimeout):
                    timeoutEx.fulfill()
                default: XCTFail()
                }
            }
        XCTAssertEqual(1, channel.pending.count)

        let socketSub = socket.sink(receiveValue: onResult(.open, channel.join()))
        defer { socketSub.cancel() }

        socket.connect()

        wait(for: [okEx], timeout: 2)
        wait(for: [timeoutEx], timeout: 0.15)
    }

    // MARK: leave

    // https://github.com/phoenixframework/phoenix/blob/118999e0fd8e8192155b787b4b71e3eb3719e7e5/assets/test/channel_test.js#L1009
    func testLeaveUnsubscribesFromServerEvents() throws {
        let channel = makeChannel(topic: "room:lobby")

        let socketSub = socket.sink(receiveValue: onResult(.open, channel.join()))
        defer { socketSub.cancel() }

        let joinEx = expectation(description: "Should have joined")
        let leaveEx = expectation(description: "Should have received leave")
        let afterLeaveEx =
            expectation(description: "Should not have received messages after leaving")
        afterLeaveEx.isInverted = true
        let channelSub = channel.sink { (event: Channel.Event) in
            switch event {
            case .join:
                joinEx.fulfill()
                channel.leave()
                channel.push("echo", callback: { _ in afterLeaveEx.fulfill() })
            case .leave:
                leaveEx.fulfill()
            default:
                afterLeaveEx.fulfill()
            }
        }
        defer { channelSub.cancel() }

        socket.connect()

        wait(for: [joinEx, leaveEx], timeout: 2, enforceOrder: true)
        wait(for: [afterLeaveEx], timeout: 0.1)
    }

    // https://github.com/phoenixframework/phoenix/blob/118999e0fd8e8192155b787b4b71e3eb3719e7e5/assets/test/channel_test.js#L1024
    // https://github.com/phoenixframework/phoenix/blob/118999e0fd8e8192155b787b4b71e3eb3719e7e5/assets/test/channel_test.js#L1034
    func testClosesChannelAfterReceivingOkResponseFromServer() throws {
        throw XCTSkip()
        
        let channel1 = makeChannel(topic: "room:lobby")
        let channel2 = makeChannel(topic: "room:lobby2")

        let socketSub = socket
            .sink(receiveValue: expectAndThen([.open: { channel1.join(); channel2.join() }]))
        defer { socketSub.cancel() }

        let channel1Sub = channel1.sink(
            receiveValue:
            expectAndThen([
                .join: {},
                .leave: { XCTAssertTrue(channel1.isClosed) },
            ])
        )
        defer { channel1Sub.cancel() }

        let channel2Sub = channel2.sink(
            receiveValue:
            expectAndThen([
                .join: { XCTAssertEqual(2, self.socket.joinedChannels.count); channel1.leave()
                },
            ])
        )
        defer { channel2Sub.cancel() }

        socket.connect()

        // The channel gets the leave response before the socket receives a close message from
        // the socket. However, the socket only removes the channel after receiving the close message.
        // So, we need to wait a while longer here to make sure the socket has received the close
        // message before testing to see if the channel has been removed from `joinedChannels`.
        expectationWithTest(
            description: "Channel should have been removed",
            test: socket.joinedChannels.count == 1
        )

        waitForExpectations(timeout: 2)

        XCTAssertEqual(1, socket.joinedChannels.count)
        XCTAssertEqual("room:lobby2", socket.joinedChannels[0].topic)
    }

    // https://github.com/phoenixframework/phoenix/blob/118999e0fd8e8192155b787b4b71e3eb3719e7e5/assets/test/channel_test.js#L1046
    func testChannelSetsStateToLeaving() throws {
        let channel = makeChannel(topic: "room:lobby")

        let channelSub = channel.sink(
            receiveValue:
            expectAndThen([
                .join: {
                    channel.leave()
                    XCTAssertTrue(channel.isLeaving)
                },
                .leave: {},
            ])
        )
        defer { channelSub.cancel() }

        let socketSub = socket.sink(receiveValue: expectAndThen(.open, channel.join()))
        defer { socketSub.cancel() }

        socket.connect()

        waitForExpectations(timeout: 2)
    }

    // TODO: `leave()` doesn't pay attention to timeouts
    // https://github.com/phoenixframework/phoenix/blob/118999e0fd8e8192155b787b4b71e3eb3719e7e5/assets/test/channel_test.js#L1054
    // https://github.com/phoenixframework/phoenix/blob/118999e0fd8e8192155b787b4b71e3eb3719e7e5/assets/test/channel_test.js#L1062
    func testClosesChannelOnTimeoutOfLeavePush() throws {
        let channel = makeChannel(topic: "room:lobby")

        let closeEx = expectation(description: "Should have closed")
        let channelSub = channel.sink(
            receiveCompletion: { _ in closeEx.fulfill() },
            receiveValue:
            expectAndThen(
                [
                    .join: {
                        channel.leave(timeout: .microseconds(1))
                        XCTAssertTrue(channel.isLeaving)
                    },
                ]
            )
        )
        defer { channelSub.cancel() }

        let socketSub = socket.sink(receiveValue: expectAndThen(.open, channel.join()))
        defer { socketSub.cancel() }

        socket.connect()

        waitForExpectations(timeout: 2)

        XCTAssertTrue(channel.isClosed)
    }

    // MARK: Extra tests

    func testReceivingReplyErrorDoesNotSetChannelStateToErrored() throws {
        let channel = makeChannel(topic: "room:lobby")

        let callback = expectError(response: ["error": "whatever"])
        let channelSub = channel.sink(
            receiveValue:
            expectAndThen([
                .join: {
                    channel.push(
                        "echo_error",
                        payload: ["error": "whatever"],
                        callback: callback
                    )
                },
            ])
        )
        defer { channelSub.cancel() }

        let socketSub = socket.autoconnect().sink(receiveValue: onResult(.open, channel.join()))
        defer { socketSub.cancel() }

        waitForExpectations(timeout: 2)

        XCTAssertEqual(channel.connectionState, "joined")
    }

    func testMultipleSocketsCollaborating() throws {
        let socket1 = Socket(url: testHelper.defaultURL)
        let socket2 = Socket(url: testHelper.defaultURL)
        defer { socket1.disconnect(); socket2.disconnect() }

        let socketSub1 = socket1.autoconnect().sink(receiveValue: expect(.open))
        let socketSub2 = socket2.autoconnect().sink(receiveValue: expect(.open))
        defer { socketSub1.cancel(); socketSub2.cancel() }

        waitForExpectations(timeout: 2)

        let channel1 = socket1.join("room:lobby")
        let channel2 = socket2.join("room:lobby")

        let joinEx = expectation(description: "Should have joined")
        joinEx.expectedFulfillmentCount = 2
        let messageEx = expectation(description: "Channel 1 should have received a message")
        let noMessageEx =
            expectation(description: "Channel 2 should not have received a message")
        noMessageEx.isInverted = true

        let channelSub1 = channel1.sink(
            receiveValue:
            onResults([.join: { joinEx.fulfill() }, .message: { messageEx.fulfill() }])
        )
        let channelSub2 = channel2.sink { (output: Channel.Output) in
            switch output {
            case .join: joinEx.fulfill()
            case .message: noMessageEx.fulfill()
            default: break
            }
        }
        defer { channelSub1.cancel(); channelSub2.cancel() }

        channel2.push("insert_message", payload: ["text": "This should get broadcasted 😎"])

        wait(for: [joinEx, messageEx], timeout: 2)
        wait(for: [noMessageEx], timeout: 0.1)
    }

    func testRejoinsAfterDisconnect() throws {
        socket.reconnectTimeInterval = { _ in .milliseconds(5) }
        let channel = makeChannel(topic: "room:lobby")
        channel.rejoinTimeout = { _ in .milliseconds(30) }
        channel.join()

        let openEx =
            expectation(description: "Should have opened twice (once after disconnect)")
        openEx.expectedFulfillmentCount = 2
        openEx.assertForOverFulfill = false

        let joinEx = expectation(description: "Should have joined channel twice")
        joinEx.expectedFulfillmentCount = 2
        joinEx.assertForOverFulfill = false

        let socketSub = socket.sink { if case .open = $0 { openEx.fulfill() } }
        defer { socketSub.cancel() }

        let channelSub = channel.sink { (event: Channel.Event) in
            guard case .join = event else { return }
            self.socket.send("disconnect")
            joinEx.fulfill()
        }
        defer { channelSub.cancel() }

        socket.connect()

        waitForExpectations(timeout: 2)
    }

    func testSendingNoReplyMessageWithCallback() throws {
        let channel = makeChannel(topic: "room:lobby")

        let socketSub = socket.sink(receiveValue: onResult(.open, channel.join()))
        defer { socketSub.cancel() }

        let expectFailure = self.expectFailure(Channel.Error.pushTimeout)
        let channelSub = channel.sink(
            receiveValue:
            expectAndThen([
                .join: {
                    channel.push(
                        "insert_message",
                        payload: ["text": "word"],
                        timeout: .milliseconds(50),
                        callback: expectFailure
                    )
                },
            ])
        )
        defer { channelSub.cancel() }

        socket.connect()

        waitForExpectations(timeout: 2)

        XCTAssertTrue(channel.pending.isEmpty)
        XCTAssertTrue(channel.inFlight.isEmpty)
        XCTAssertTrue(channel.isJoined)
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
        channel.rejoinTimeout = { _ in .seconds(30) }
        return channel
    }
}
