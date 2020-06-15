import XCTest
@testable import Phoenix
import Combine

class SocketTests: XCTestCase {

    // MARK: init, connect, and disconnect

    // https://github.com/phoenixframework/phoenix/blob/14f177a7918d1bc04e867051c4fd011505b22c00/assets/test/socket_test.js#L24
    func testSocketInit() throws {
        // https://github.com/phoenixframework/phoenix/blob/14f177a7918d1bc04e867051c4fd011505b22c00/assets/test/socket_test.js#L33
        XCTAssertEqual(Socket.defaultTimeout, .seconds(10))

        // https://github.com/phoenixframework/phoenix/blob/14f177a7918d1bc04e867051c4fd011505b22c00/assets/test/socket_test.js#L35
        XCTAssertEqual(Socket.defaultHeartbeatInterval, .seconds(30))
        
        let url: URL = URL(string: "ws://0.0.0.0:4000/socket")!
        let socket = Socket(url: url)
        
        XCTAssertEqual(socket.timeout, Socket.defaultTimeout)
        XCTAssertEqual(socket.heartbeatInterval, Socket.defaultHeartbeatInterval)
        
        XCTAssertEqual(socket.currentRef, 0)
        XCTAssertEqual(socket.url.path, "/socket/websocket")
        XCTAssertEqual(socket.url.query, "vsn=2.0.0")
    }

    // https://github.com/phoenixframework/phoenix/blob/14f177a7918d1bc04e867051c4fd011505b22c00/assets/test/socket_test.js#L49
    func testSocketInitOverrides() throws {
        let socket = Socket(
            url: testHelper.defaultURL,
            timeout: .seconds(20),
            heartbeatInterval: .seconds(40)
        )
        
        XCTAssertEqual(socket.timeout, .seconds(20))
        XCTAssertEqual(socket.heartbeatInterval, .seconds(40))
    }

    // https://github.com/phoenixframework/phoenix/blob/14f177a7918d1bc04e867051c4fd011505b22c00/assets/test/socket_test.js#L297
    func testSocketDisconnectIsNoOp() throws {
        let socket = makeSocket()
        socket.disconnect()
    }

    // https://github.com/phoenixframework/phoenix/blob/14f177a7918d1bc04e867051c4fd011505b22c00/assets/test/socket_test.js#L242
    func testSocketConnectIsNoOp() throws {
        let socket = makeSocket()

        socket.connect()
        socket.connect() // calling connect again doesn't blow up
    }


    // https://github.com/phoenixframework/phoenix/blob/14f177a7918d1bc04e867051c4fd011505b22c00/assets/test/socket_test.js#L153
    func testSocketConnectAndDisconnect() throws {
        let socket = makeSocket()

        let sub = socket.forever(receiveValue:
            expectAndThen([
                .open: { socket.disconnect() },
                .close: { }
            ])
        )
        defer { sub.cancel() }

        socket.connect()

        waitForExpectations(timeout: 2)
    }

    // https://github.com/phoenixframework/phoenix/blob/14f177a7918d1bc04e867051c4fd011505b22c00/assets/test/socket_test.js#L161
    func testSocketConnectDisconnectAndReconnect() throws {
        let socket = makeSocket()
        
        let closeMessageEx = expectation(description: "Should have received a close message")
        let openMesssageEx = expectation(description: "Should have received an open message")
        let reopenMessageEx = expectation(description: "Should have reopened and got an open message")
        
        var openExs = [reopenMessageEx, openMesssageEx]

        let sub = socket.forever(receiveValue:
            onResults([
                .open: { openExs.popLast()?.fulfill(); if !openExs.isEmpty { socket.disconnect() } },
                .close: { closeMessageEx.fulfill(); socket.connect() }
            ])
        )
        defer { sub.cancel() }

        socket.connect()

        waitForExpectations(timeout: 2)
    }
    
    func testSocketAutoconnectHasUpstream() throws {
        let conn = makeSocket().autoconnect()
        defer { conn.upstream.disconnect() }

        let sub = conn.forever(receiveValue: expect(.open))
        defer { sub.cancel() }

        waitForExpectations(timeout: 2)
    }
    
    func testSocketAutoconnectSubscriberCancelDisconnects() throws {
        let socket = makeSocket()

        let sub = socket.forever(receiveValue:
            expectAndThen([
                .close: { XCTAssertEqual(socket.connectionState, "closed") }
            ])
        )
        defer { sub.cancel() }

        var autoSub: Subscribers.Forever<Publishers.Autoconnect<Socket>>? = nil
        autoSub = socket.autoconnect().forever(receiveValue:
            expectAndThen([
                .open: {
                    XCTAssertEqual(socket.connectionState, "open")
                    autoSub?.cancel()
                }
            ])
        )
        defer { autoSub?.cancel() }

        waitForExpectations(timeout: 2)
    }
    
    // MARK: connection state

    // https://github.com/phoenixframework/phoenix/blob/14f177a7918d1bc04e867051c4fd011505b22c00/assets/test/socket_test.js#L309
    func testSocketDefaultsToClosed() throws {
        let socket = makeSocket()
        XCTAssertEqual(socket.connectionState, "closed")
        XCTAssert(socket.isClosed)
    }

    // https://github.com/phoenixframework/phoenix/blob/14f177a7918d1bc04e867051c4fd011505b22c00/assets/test/socket_test.js#L320
    func testSocketIsConnecting() throws {
        let socket = makeSocket()

        self.expectationWithTest(description: "Socket enters connecting state", test: socket.isConnecting)
        let sub = socket.autoconnect().forever(receiveValue: expect(.connecting))
        defer { sub.cancel() }

        waitForExpectations(timeout: 2)
    }

    // https://github.com/phoenixframework/phoenix/blob/14f177a7918d1bc04e867051c4fd011505b22c00/assets/test/socket_test.js#L328
    func testSocketIsOpen() throws {
        let socket = makeSocket()

        self.expectationWithTest(description: "Socket enters open state", test: socket.isOpen)
        let sub = socket.autoconnect().forever(receiveValue: expect(.open))
        defer { sub.cancel() }

        waitForExpectations(timeout: 2)
    }

    // https://github.com/phoenixframework/phoenix/blob/14f177a7918d1bc04e867051c4fd011505b22c00/assets/test/socket_test.js#L336
    func testSocketIsClosing() throws {
        let socket = makeSocket()

        self.expectationWithTest(description: "Socket enters closing state", test: socket.isClosing)
        let sub = socket.autoconnect().forever(receiveValue:
            expectAndThen([
                .open: { socket.disconnect() },
                .closing: { }
            ])
        )
        defer { sub.cancel() }

        waitForExpectations(timeout: 2)
    }

    // https://github.com/phoenixframework/phoenix/blob/14f177a7918d1bc04e867051c4fd011505b22c00/assets/test/socket_test.js#L344
    // https://github.com/phoenixframework/phoenix/blob/14f177a7918d1bc04e867051c4fd011505b22c00/assets/test/socket_test.js#L277
    // https://github.com/phoenixframework/phoenix/blob/14f177a7918d1bc04e867051c4fd011505b22c00/assets/test/socket_test.js#L287
    func testSocketIsClosed() throws {
        let socket = makeSocket()

        let sub = socket.autoconnect().forever(receiveValue:
            expectAndThen([
                .open: { socket.disconnect() },
                .close: {
                    XCTAssertEqual(socket.connectionState, "closed")
                    XCTAssert(socket.isClosed)
                    XCTAssertFalse(socket.isOpen)
                }
            ])
        )
        defer { sub.cancel() }

        waitForExpectations(timeout: 2)
    }
    
    func testSocketIsConnectedEvenAfterSubscriptionIsCancelled() throws {
        let socket = makeSocket()

        let closeMessageEx = expectation(description: "Shouldn't have closed")
        closeMessageEx.isInverted = true

        let openEx = expectation(description: "Should have gotten an open message")

        var sub: Subscribers.Forever<Socket>? = nil
        sub = socket.forever(receiveValue:
            onResults([
                .open: { openEx.fulfill(); sub?.cancel() },
                .closing: { closeMessageEx.fulfill() },
                .close: { closeMessageEx.fulfill() },
            ])
        )

        socket.connect()

        wait(for: [openEx], timeout: 2)
        wait(for: [closeMessageEx], timeout: 0.2)
        XCTAssertEqual(socket.connectionState, "open")
    }

    func testSocketIsDisconnectedAfterAutconnectSubscriptionIsCancelled() throws {
        let socket = makeSocket()

        var sub: Subscribers.Forever<Publishers.Autoconnect<Socket>>? = nil
        sub = socket.autoconnect().forever(receiveValue:
            expectAndThen([
                 .open: { sub?.cancel() },
            ])
        )

        self.expectationWithTest(description: "Socket did close", test: socket.isClosed)

        waitForExpectations(timeout: 2)
    }

    // https://github.com/phoenixframework/phoenix/blob/a1120f6f292b44ab2ad1b673a937f6aa2e63c225/assets/test/socket_test.js#L268
    // https://github.com/phoenixframework/phoenix/blob/14f177a7918d1bc04e867051c4fd011505b22c00/assets/test/socket_test.js#L297
    func testDisconnectTwiceOnlySendsMessagesOnce() throws {
        let socket = makeSocket()

        let openEx = expectation(description: "Should have opened once")
        let closeMessageEx = expectation(description: "Should closed once")

        let sub = socket.forever(receiveValue:
            onResults([
                .open: { openEx.fulfill(); socket.disconnect() },
                .close: {
                    socket.disconnect()
                    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) { closeMessageEx.fulfill()
                    }
                },
            ])
        )
        defer { sub.cancel() }

        socket.connect()

        waitForExpectations(timeout: 2)
    }
    
    // MARK: channel
    
    func testChannelInit() throws {
        let socket = makeSocket()
        socket.connect()

        let channel = socket.join("room:lobby")
        defer { channel.leave() }

        let sub = channel.forever(receiveValue: expect(.join))
        defer { sub.cancel() }

        waitForExpectations(timeout: 2.0)
    }

    // https://github.com/phoenixframework/phoenix/blob/a1120f6f292b44ab2ad1b673a937f6aa2e63c225/assets/test/socket_test.js#L360
    func testChannelInitWithParams() throws {
        let socket = makeSocket()
        let channel = socket.join("room:lobby", payload: ["success": true])
        
        XCTAssertEqual(channel.topic, "room:lobby")
        XCTAssertEqual(channel.joinPush.payload["success"] as? Bool, true)
    }

    // https://github.com/phoenixframework/phoenix/blob/a1120f6f292b44ab2ad1b673a937f6aa2e63c225/assets/test/socket_test.js#L368
    func testChannelsAreTracked() throws {
        let socket = makeSocket()
        let channel1 = socket.join("room:lobby")
        
        XCTAssertEqual(socket.joinedChannels.count, 1)
        
        let channel2 = socket.join("room:lobby2")
        
        XCTAssertEqual(socket.joinedChannels.count, 2)
        
        XCTAssertEqual(channel1.connectionState, "joining")
        XCTAssertEqual(channel2.connectionState, "joining")
    }

    // TODO: Fix deadlock in `testChannelsAreRemoved()`
    // https://github.com/phoenixframework/phoenix/blob/a1120f6f292b44ab2ad1b673a937f6aa2e63c225/assets/test/socket_test.js#L385
    func testChannelsAreRemoved() throws {
        let socket = makeSocket()
        socket.connect()

        let channel1 = socket.channel("room:lobby")
        let channel2 = socket.channel("room:lobby2")

        let sub1 = channel1.forever(receiveValue: expect(.join))
        let sub2 = channel2.forever(receiveValue: expect(.join))
        defer { [sub1, sub2].forEach { $0.cancel() } }

        socket.join(channel1)
        socket.join(channel2)

        waitForExpectations(timeout: 2)

        XCTAssertEqual(Set(["room:lobby", "room:lobby2"]), Set(socket.joinedChannels.map(\.topic)))

        socket.leave(channel1)

        let sub3 = channel1.forever(receiveValue: expect(.leave))
        defer { sub3.cancel() }

        waitForExpectations(timeout: 2)

        XCTAssertEqual(["room:lobby2"], socket.joinedChannels.map(\.topic))
    }
    
    // MARK: push

    // https://github.com/phoenixframework/phoenix/blob/a1120f6f292b44ab2ad1b673a937f6aa2e63c225/assets/test/socket_test.js#L413
    func testPushOntoSocket() throws {
        let socket = makeSocket()

        let expectPushSuccess = self.expectPushSuccess()
        let sub = socket.autoconnect().forever(receiveValue:
            expectAndThen([
                .open: {
                    socket.push(topic: "phoenix", event: .heartbeat, callback: expectPushSuccess)
                }
            ])
        )
        defer { sub.cancel() }

        waitForExpectations(timeout: 2)
    }

    // https://github.com/phoenixframework/phoenix/blob/a1120f6f292b44ab2ad1b673a937f6aa2e63c225/assets/test/socket_test.js#L424
    func testPushOntoDisconnectedSocketBuffers() throws {
        let socket = makeSocket()

        let expectPushSuccess = self.expectPushSuccess()
        socket.push(topic: "phoenix", event: .heartbeat, callback: expectPushSuccess)

        XCTAssertTrue(socket.isClosed)
        XCTAssertEqual(1, socket.pendingPushes.count)
        XCTAssertEqual("phoenix", socket.pendingPushes.first?.topic)
        XCTAssertEqual(PhxEvent.heartbeat, socket.pendingPushes.first?.event)

        socket.connect()

        waitForExpectations(timeout: 2)
    }
    
    // MARK: heartbeat

    // https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L470
    func testHeartbeatTimeoutMovesSocketToClosedState() throws {
        let socket = makeSocket()

        let sub = socket.autoconnect().forever(receiveValue:
            expectAndThen([
                // Attempting to send a heartbeat before the previous one has returned causes the socket to timeout
                .open: { socket.sendHeartbeat(); socket.sendHeartbeat() },
                .close: { }
            ])
        )
        defer { sub.cancel() }

        waitForExpectations(timeout: 2)
    }

    // https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L481
    func testPushesHeartbeatWhenConnected() throws {
        let socket = makeSocket()

        let heartbeatExpectation = self.expectation(description: "Sends heartbeat when connected")

        let sub = socket.autoconnect().forever(receiveValue:
            expectAndThen([
                .open: { socket.sendHeartbeat { heartbeatExpectation.fulfill(); socket.disconnect() } },
                .close: { }
            ])
        )
        defer { sub.cancel() }

        waitForExpectations(timeout: 2)
    }
    
    func testHeartbeatTimeoutIndirectlyWithWayTooSmallInterval() throws {
        let socket = Socket(url: testHelper.defaultURL, heartbeatInterval: .milliseconds(1))

        let sub = socket.autoconnect().forever(receiveValue: expect(.close))
        defer { sub.cancel() }

        waitForExpectations(timeout: 2)
    }

    // https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L491
    func testHeartbeatIsNotSentWhenDisconnected() {
        let socket = makeSocket()

        let noHeartbeatExpectation = self.expectation(description: "Does not send heartbeat when disconnected")
        noHeartbeatExpectation.isInverted = true

        let sub = socket.forever(receiveValue: onResult(.close, noHeartbeatExpectation.fulfill()))
        defer { sub.cancel() }

        socket.sendHeartbeat { noHeartbeatExpectation.fulfill() }

        waitForExpectations(timeout: 0.1)
    }
    
    // MARK: on open

    // https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L508
    // https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L551
    func testFlushesPushesOnOpen() throws {
        let socket = makeSocket()

        let receivedResponses = self.expectation(description: "Received response")
        receivedResponses.expectedFulfillmentCount = 2

        socket.push(topic: "unknown", event: .custom("one"))
        socket.push(topic: "unknown", event: .custom("two"))

        let sub = socket.autoconnect().forever { message in
            switch message {
            case .incomingMessage(let incoming):
                guard let response = incoming.payload["response"] as? Dictionary<String, String> else { return }
                guard let reason = response["reason"], reason == "unmatched topic" else { return }
                receivedResponses.fulfill()
            default:
                break
            }
        }
        defer { sub.cancel() }

        waitForExpectations(timeout: 2)
    }

    // https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L523
    func testFlushesAllQueuedMessages() throws {
        let socket = makeSocket()

        let receivedResponses = self.expectation(description: "Received response")
        receivedResponses.expectedFulfillmentCount = 3

        socket.push(topic: "unknown", event: .custom("one"))
        socket.push(topic: "unknown", event: .custom("two"))
        socket.push(topic: "unknown", event: .custom("three"))

        let sub = socket.autoconnect().forever { message in
            switch message {
            case .incomingMessage:
                receivedResponses.fulfill()
            default:
                break
            }
        }
        defer { sub.cancel() }

        waitForExpectations(timeout: 2)

        XCTAssertTrue(socket.pendingPushes.isEmpty)
    }

    func testDefaultReconnectTimeInterval() {
        let socket = Socket(url: testHelper.defaultURL)

        let expected: [Int: DispatchTimeInterval] = [
            1: .milliseconds(10),
            2: .milliseconds(50),
            3: .milliseconds(100),
            4: .milliseconds(150),
            5: .milliseconds(200),
            6: .milliseconds(250),
            7: .milliseconds(500),
            8: .milliseconds(1000),
            9: .milliseconds(2000),
            10: .milliseconds(5000),
            11: .milliseconds(5000),
            99: .milliseconds(5000),
        ]

        expected.forEach { (attempt: Int, timeInterval: DispatchTimeInterval) in
            XCTAssertEqual(timeInterval, socket.reconnectTimeInterval(attempt))
        }
    }

    // https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L561
    func testConnectionOpenResetsReconnectTimer() {
        let socket = makeSocket()
        socket.reconnectAttempts = 123

        let sub = socket.autoconnect().forever(receiveValue: expect(.open))
        defer { sub.cancel() }

        waitForExpectations(timeout: 2)

        XCTAssertEqual(0, socket.reconnectAttempts)
    }

    // https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L569
    func testConnectionOpenPublishesOpenMessage() {
        let socket = makeSocket()

        let sub = socket.autoconnect().forever(receiveValue: expect(.open))
        defer { sub.cancel() }

        waitForExpectations(timeout: 2)
    }
    
    // MARK: socket connection close

    // https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L598
    func testSocketReconnectAfterRemoteClose() throws {
        let socket = makeSocket()
        socket.reconnectTimeInterval = { _ in .milliseconds(10) }

        let open = self.expectation(description: "Opened multiple times")
        open.assertForOverFulfill = false
        open.expectedFulfillmentCount = 2

        let sub = socket.autoconnect().forever(receiveValue:
            onResults([
                .open: { open.fulfill(); socket.send("disconnect") }
            ])
        )
        defer { sub.cancel() }

        waitForExpectations(timeout: 2)
    }

    // https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L608
    func testSocketDoesNotReconnectIfExplicitDisconnect() throws {
        let socket = makeSocket()
        socket.reconnectTimeInterval = { _ in .milliseconds(10) }

        let sub1 = socket.autoconnect().forever(receiveValue:
            expectAndThen([.open: { socket.disconnect() }])
        )
        defer { sub1.cancel() }

        waitForExpectations(timeout: 2)

        let notOpen = self.expectation(description: "Not opened again")
        notOpen.isInverted = true
        let sub2 = socket.forever(receiveValue: onResult(.open, notOpen.fulfill()))
        defer { sub2.cancel() }

        waitForExpectations(timeout: 0.1)
    }

    // https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L618
    func testSocketReconnectAfterRemoteException() throws {
        let socket = makeSocket()
        socket.reconnectTimeInterval = { _ in .milliseconds(10) }

        let open = self.expectation(description: "Opened multiple times")
        open.assertForOverFulfill = false
        open.expectedFulfillmentCount = 2

        let sub = socket.autoconnect().forever(receiveValue:
            onResults([
                .open: { open.fulfill(); socket.send("boom") }
            ])
        )
        defer { sub.cancel() }

        waitForExpectations(timeout: 2)
    }

    // https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L628
    func testSocketReconnectsAfterExplicitDisconnectAndThenConnect() throws {
        let socket = makeSocket()
        socket.reconnectTimeInterval = { _ in .milliseconds(10) }

        let sub1 = socket.autoconnect().forever(receiveValue:
            expectAndThen([
                .open: { socket.disconnect() },
                .close: { },
            ])
        )
        waitForExpectations(timeout: 2)
        sub1.cancel()

        let doesNotReconnect = self.expectation(description: "Does not reconnect after disconnect")
        doesNotReconnect.isInverted = true
        let sub2 = socket.forever(receiveValue: onResult(.open, doesNotReconnect.fulfill()))
        waitForExpectations(timeout: 0.1)
        sub2.cancel()

        let reconnects = self.expectation(description: "Reconnects again after explicit connect")
        reconnects.expectedFulfillmentCount = 2
        reconnects.assertForOverFulfill = false
        let sub3 = socket.forever(receiveValue:
            onResults([
                .open: {
                    reconnects.fulfill()
                    socket.send("boom")
                }
            ])
        )
        defer { sub3.cancel() }
        socket.connect()
        waitForExpectations(timeout: 2)
    }

    // https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L643
    func testRemoteClosePublishesClose() throws {
        let socket = makeSocket()

        let sub = socket.autoconnect().forever(receiveValue:
            expectAndThen([
                .open: { socket.send("disconnect") },
                .close: { },
            ])
        )
        defer { sub.cancel() }

        waitForExpectations(timeout: 2)
    }

    // https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L664
    func testRemoteExceptionErrorsChannels() throws {
        let socket = makeSocket()
        let channel = socket.join("room:lobby")

        let sub = channel.forever(receiveValue:
            expectAndThen([
                .join: { socket.send("boom") },
                .error: { },
            ])
        )
        defer { sub.cancel() }
        socket.connect()

        waitForExpectations(timeout: 2)
    }

    // https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L664
    func testSocketCloseErrorsChannels() throws {
        let socket = makeSocket()
        let channel = socket.join("room:lobby")

        let sub = channel.forever(receiveValue:
            expectAndThen([
                .join: { socket.send("disconnect") },
                .error: { }
            ])
        )
        defer { sub.cancel() }
        socket.connect()

        waitForExpectations(timeout: 2)
    }

    // https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L676
    func testSocketCloseDoesNotErrorChannelsIfLeft() throws {
        let socket = makeSocket()
        socket.reconnectTimeInterval = { _ in .milliseconds(10) }

        let channel = socket.join("room:lobby")

        let sub1 = channel.forever(receiveValue:
            expectAndThen([
                .join: { socket.leave(channel) },
                .leave: { }
            ])
        )
        socket.connect()

        waitForExpectations(timeout: 2)
        sub1.cancel()

        let noError = self.expectation(description: "Should not have received an error")
        noError.isInverted = true

        let sub2 = channel.forever(receiveValue: onResult(.error, noError.fulfill()))
        defer { sub2.cancel() }

        socket.send("disconnect")

        waitForExpectations(timeout: 0.1)
    }
    
    func testRemoteExceptionPublishesError() throws {
        let socket = makeSocket()

        let sub = socket.autoconnect().forever(receiveValue:
            expectAndThen([
                .open: { socket.send("boom") },
                .websocketError: { }
            ])
        )
        defer { sub.cancel() }

        waitForExpectations(timeout: 2)
    }
    
    // MARK: channel messages

    func testChannelReceivesMessages() throws {
        let socket = makeSocket()

        let channel = socket.join("room:lobby")
        let echoEcho = "yahoo"
        let echoEx = expectation(description: "Should have received the echo text response")

        channel.push("echo", payload: ["echo": echoEcho]) { result in
            guard case .success(let reply) = result else { return }
            XCTAssertTrue(reply.isOk)
            XCTAssertEqual(socket.currentRef, reply.ref)
            XCTAssertEqual(channel.topic, reply.incomingMessage.topic)
            XCTAssertEqual(["echo": echoEcho], reply.response as? Dictionary<String, String>)
            XCTAssertEqual(channel.joinRef, reply.joinRef)
            echoEx.fulfill()
        }

        socket.connect()

        waitForExpectations(timeout: 2)
    }
    
    func testSocketDecodesAndPublishesMessage() throws {
        let socket = makeSocket()
        defer { socket.disconnect() }
        
        let channel = socket.join("room:lobby")
        
        let echoEcho = "kapow"
        let echoEx = expectation(description: "Should have received the echo text response")
        
        let sub = socket.autoconnect().forever {
            if case .incomingMessage(let message) = $0,
                message.topic == channel.topic,
                message.event == .reply,
                message.payload["status"] as? String == "ok",
                let response = message.payload["response"] as? [String: String],
                response["echo"] == echoEcho {
                
                echoEx.fulfill()
            }
        }
        defer { sub.cancel() }
        
        channel.push("echo", payload: ["echo": echoEcho])
        
        waitForExpectations(timeout: 1)
    }
}

private extension SocketTests {
    func makeSocket() -> Socket {
        let socket = Socket(url: testHelper.defaultURL)
        // We don't want the socket to reconnect unless the test requires it to.
        socket.reconnectTimeInterval = { _ in .seconds(30) }
        return socket
    }

    func assertOpen(_ socket: Socket) {
        let openEx = expectation(description: "Should have gotten an open message");

        let sub = socket.forever {
            if case .open = $0 { openEx.fulfill() }
        }
        defer { sub.cancel() }

        socket.connect()

        wait(for: [openEx], timeout: 1)
    }

    func expectPushSuccess() -> (Error?) -> Void {
        let pushSuccess = self.expectation(description: "Should have received response")
        return { e in
            if let error = e {
                Swift.print("Couldn't write to socket with error '\(error)'")
                XCTFail()
            } else {
                pushSuccess.fulfill()
            }
        }
    }

    func expect<T: RawCaseConvertible>(_ value: T.RawCase) -> (T) -> Void {
        let expectation = self.expectation(description: "Should have received '\(String(describing: value))'")
        return { v in
            if v.matches(value) {
                expectation.fulfill()
            }
        }
    }

    func expectAndThen<T: RawCaseConvertible>(_ valueToAction: Dictionary<T.RawCase, (() -> Void)>) -> (T) -> Void {
        let valueToExpectation = valueToAction.reduce(into: Dictionary<T.RawCase, XCTestExpectation>())
        { [unowned self] (dict, valueToAction) in
            let key = valueToAction.key
            let expectation = self.expectation(description: "Should have received '\(String(describing: key))'")
            dict[key] = expectation
        }

        return { v in
            let rawCase = v.toRawCase()
            if let block = valueToAction[rawCase], let expectation = valueToExpectation[rawCase] {
                expectation.fulfill()
                block()
            }
        }
    }

    func onResult<T: RawCaseConvertible>(_ value: T.RawCase, _ block: @escaping @autoclosure () -> Void) -> (T) -> Void {
        return { v in
            guard v.matches(value) else { return }
            block()
        }
    }

    func onResults<T: RawCaseConvertible>(_ valueToAction: Dictionary<T.RawCase, (() -> Void)>) -> (T) -> Void {
        return { v in
            if let block = valueToAction[v.toRawCase()] {
                block()
            }
        }
    }
}
