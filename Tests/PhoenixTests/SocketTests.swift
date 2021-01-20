import XCTest
@testable import Phoenix
import Combine
import WebSocketProtocol

class SocketTests: XCTestCase {
    // MARK: init, connect, and disconnect

    // https://github.com/phoenixframework/phoenix/blob/14f177a7918d1bc04e867051c4fd011505b22c00/assets/test/socket_test.js#L24
    func testSocketInit() throws {
        // https://github.com/phoenixframework/phoenix/blob/14f177a7918d1bc04e867051c4fd011505b22c00/assets/test/socket_test.js#L33
        XCTAssertEqual(Socket.defaultTimeout, .seconds(10))

        // https://github.com/phoenixframework/phoenix/blob/14f177a7918d1bc04e867051c4fd011505b22c00/assets/test/socket_test.js#L35
        XCTAssertEqual(Socket.defaultHeartbeatInterval, .seconds(30))

        let url: URL = URL(string: "ws://0.0.0.0:4003/socket")!
        let socket = Socket(url: url)

        XCTAssertEqual(socket.timeout, Socket.defaultTimeout)
        XCTAssertEqual(socket.heartbeatInterval, Socket.defaultHeartbeatInterval)

        XCTAssertEqual(socket.currentRef, 0)
        XCTAssertEqual(socket.url.path, "/socket/websocket")
        XCTAssertEqual(socket.url.query, "vsn=2.0.0")
        socket.disconnectAndWait()
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
        socket.disconnectAndWait()
    }

    // https://github.com/phoenixframework/phoenix/blob/14f177a7918d1bc04e867051c4fd011505b22c00/assets/test/socket_test.js#L297
    func testSocketDisconnectIsNoOp() throws {
        try withSocket { $0.disconnect() }
    }

    // https://github.com/phoenixframework/phoenix/blob/14f177a7918d1bc04e867051c4fd011505b22c00/assets/test/socket_test.js#L242
    func testSocketConnectIsNoOp() throws {
        try withSocket { (socket) in
            socket.connect()
            socket.connect() // calling connect again doesn't blow up
        }
    }

    // https://github.com/phoenixframework/phoenix/blob/14f177a7918d1bc04e867051c4fd011505b22c00/assets/test/socket_test.js#L153
    func testSocketConnectAndDisconnect() throws {
        try withSocket { (socket) in
            let sub = socket.sink(receiveValue:
                expectAndThen([
                    .open: { socket.disconnect() },
                    .close: { }
                ])
            )
            defer { sub.cancel() }

            socket.connect()

            waitForExpectations(timeout: 2)
        }
    }

    // https://github.com/phoenixframework/phoenix/blob/14f177a7918d1bc04e867051c4fd011505b22c00/assets/test/socket_test.js#L161
    func testSocketConnectDisconnectAndReconnect() throws {
        try withSocket { (socket) in
            let closeMessageEx = expectation(description: "Should have received a close message")
            let openMesssageEx = expectation(description: "Should have received an open message")
            let reopenMessageEx = expectation(description: "Should have reopened and got an open message")

            var openExs = [reopenMessageEx, openMesssageEx]

            let sub = socket.sink(receiveValue:
                onResults([
                    .open: { openExs.popLast()?.fulfill(); if !openExs.isEmpty { socket.disconnect() } },
                    .close: { closeMessageEx.fulfill(); socket.connect() }
                ])
            )
            defer { sub.cancel() }

            socket.connect()

            waitForExpectations(timeout: 2)
        }
    }

    func testSocketAutoconnectHasUpstream() throws {
        try withSocket { (socket) in
            let conn = socket.autoconnect()
            let sub = conn.sink(receiveValue:
                expectAndThen([
                    .open: { conn.upstream.disconnect() }
                ])
            )
            defer { sub.cancel() }
            waitForExpectations(timeout: 2)
        }
    }

    func testSocketAutoconnectSubscriberCancelDisconnects() throws {
        try withSocket { (socket) in
            let sub = socket.sink(receiveValue:
                expectAndThen([
                    .close: { XCTAssertEqual(socket.connectionState, "closed") }
                ])
            )
            defer { sub.cancel() }

            var autoSub: AnyCancellable? = nil
            autoSub = socket.autoconnect().sink(receiveValue:
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
    }

    // MARK: connection state

    // https://github.com/phoenixframework/phoenix/blob/14f177a7918d1bc04e867051c4fd011505b22c00/assets/test/socket_test.js#L309
    func testSocketDefaultsToClosed() throws {
        try withSocket { (socket) in
            XCTAssertEqual(socket.connectionState, "closed")
            XCTAssert(socket.isClosed)
        }
    }

    // https://github.com/phoenixframework/phoenix/blob/14f177a7918d1bc04e867051c4fd011505b22c00/assets/test/socket_test.js#L320
    func testSocketIsConnecting() throws {
        try withSocket { (socket) in
            self.expectationWithTest(description: "Socket enters connecting state", test: socket.isConnecting)
            let sub = socket.sink(receiveValue: expect(.connecting))
            defer { sub.cancel() }
            socket.connect()

            waitForExpectations(timeout: 2)
        }
    }

    // https://github.com/phoenixframework/phoenix/blob/14f177a7918d1bc04e867051c4fd011505b22c00/assets/test/socket_test.js#L328
    func testSocketIsOpen() throws {
        try withSocket { (socket) in
            let openEx = self.expectation(description: "Socket enters open state")
            socket.onStateChange = { state in
                guard case .open = state else { return }
                openEx.fulfill()
            }
            let sub = socket.autoconnect().sink(receiveValue: expect(.open))
            defer { sub.cancel() }

            waitForExpectations(timeout: 2)
        }
    }

    // https://github.com/phoenixframework/phoenix/blob/14f177a7918d1bc04e867051c4fd011505b22c00/assets/test/socket_test.js#L336
    func testSocketIsClosing() throws {
        try withSocket { (socket) in
            let closingEx = self.expectation(description: "Socket enters closing state")
            socket.onStateChange = { state in
                guard case .closing = state else { return }
                closingEx.fulfill()
            }
            let sub = socket.autoconnect().sink(receiveValue:
                expectAndThen([
                    .open: { socket.disconnect() },
                    .closing: { }
                ])
            )
            defer { sub.cancel() }

            waitForExpectations(timeout: 2)
        }
    }

    // https://github.com/phoenixframework/phoenix/blob/14f177a7918d1bc04e867051c4fd011505b22c00/assets/test/socket_test.js#L344
    // https://github.com/phoenixframework/phoenix/blob/14f177a7918d1bc04e867051c4fd011505b22c00/assets/test/socket_test.js#L277
    // https://github.com/phoenixframework/phoenix/blob/14f177a7918d1bc04e867051c4fd011505b22c00/assets/test/socket_test.js#L287
    func testSocketIsClosed() throws {
        try withSocket { (socket) in
            let sub = socket.autoconnect().sink(receiveValue:
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
    }

    func testSocketIsConnectedEvenAfterSubscriptionIsCancelled() throws {
        try withSocket { (socket) in
            let closeMessageEx = expectation(description: "Shouldn't have closed")
            closeMessageEx.isInverted = true

            let openEx = expectation(description: "Should have gotten an open message")

            var sub: AnyCancellable? = nil
            sub = socket.sink(receiveValue:
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
    }

    func testSocketIsDisconnectedAfterAutconnectSubscriptionIsCancelled() throws {
        try withSocket { (socket) in
            var sub: AnyCancellable? = nil
            sub = socket.autoconnect().sink(receiveValue:
                expectAndThen([
                    .open: { sub?.cancel() },
                ])
            )

            let closedEx = self.expectation(description: "Socket enters closed state")
            socket.onStateChange = { state in
                guard case .closed = state else { return }
                closedEx.fulfill()
            }

            waitForExpectations(timeout: 2)
        }
    }

    // https://github.com/phoenixframework/phoenix/blob/a1120f6f292b44ab2ad1b673a937f6aa2e63c225/assets/test/socket_test.js#L268
    // https://github.com/phoenixframework/phoenix/blob/14f177a7918d1bc04e867051c4fd011505b22c00/assets/test/socket_test.js#L297
    func testDisconnectTwiceOnlySendsMessagesOnce() throws {
        try withSocket { (socket) in
            let openEx = expectation(description: "Should have opened once")
            let closeMessageEx = expectation(description: "Should closed once")

            let sub = socket.sink(receiveValue:
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
    }

    // MARK: channel

    func testChannelInit() throws {
        try withSocket { (socket) in
            socket.connect()

            let channel = socket.join("room:lobby")
            defer { channel.leave() }

            let sub = channel.sink(receiveValue: expect(.join))
            defer { sub.cancel() }

            waitForExpectations(timeout: 2)
        }
    }

    // https://github.com/phoenixframework/phoenix/blob/a1120f6f292b44ab2ad1b673a937f6aa2e63c225/assets/test/socket_test.js#L360
    func testChannelInitWithParams() throws {
        try withSocket { (socket) in
            let channel = socket.join("room:lobby", payload: ["success": true])
            XCTAssertEqual(channel.topic, "room:lobby")
            XCTAssertEqual(channel.joinPush.payload["success"] as? Bool, true)
        }
    }

    // https://github.com/phoenixframework/phoenix/blob/a1120f6f292b44ab2ad1b673a937f6aa2e63c225/assets/test/socket_test.js#L368
    func testChannelsAreTracked() throws {
        try withSocket { (socket) in
            let channel1 = socket.join("room:timeout1", payload: ["timeout": 2_000, "join": true])
            XCTAssertEqual(socket.joinedChannels.count, 1)

            let channel2 = socket.join("room:timeout2", payload: ["timeout": 2_000, "join": true])
            XCTAssertEqual(socket.joinedChannels.count, 2)

            let ex1 = expectation(description: "Should start joining channel 1")
            channel1.onStateChange = { (newState: Channel.State) in
                switch newState {
                case .joining: ex1.fulfill()
                default: break
                }
            }

            let ex2 = expectation(description: "Should start joining channel 2")
            channel2.onStateChange = { (newState: Channel.State) in
                switch newState {
                case .joining: ex2.fulfill()
                default: break
                }
            }

            waitForExpectations(timeout: 2)
        }
    }

    // https://github.com/phoenixframework/phoenix/blob/a1120f6f292b44ab2ad1b673a937f6aa2e63c225/assets/test/socket_test.js#L385
    func testChannelsAreRemoved() throws {
        try withSocket { (socket) in
            let channel1 = socket.channel("room:lobby")
            let channel2 = socket.channel("room:lobby2")

            let sub1 = channel1.sink(receiveValue: expect(.join))
            let sub2 = channel2.sink(receiveValue: expect(.join))
            defer { [sub1, sub2].forEach { $0.cancel() } }

            let socketSub = socket.autoconnect().sink(receiveValue:
                expectAndThen([.open: { socket.join(channel1); socket.join(channel2) }])
            )
            defer { socketSub.cancel() }

            waitForExpectations(timeout: 2)

            XCTAssertEqual(
                Set(["room:lobby", "room:lobby2"]),
                Set(socket.joinedChannels.map(\.topic))
            )

            socket.leave(channel1)

            let sub3 = channel1.sink(receiveValue: expect(.leave))
            defer { sub3.cancel() }

            // The channel gets the leave response before the socket receives a close message from
            // the socket. However, the socket only removes the channel after receiving the close message.
            // So, we need to wait a while longer here to make sure the socket has received the close
            // message before testing to see if the channel has been removed from `joinedChannels`.
            expectationWithTest(
                description: "Channel should have been removed",
                test: socket.joinedChannels.count == 1
            )

            waitForExpectations(timeout: 2)

            XCTAssertEqual(["room:lobby2"], socket.joinedChannels.map(\.topic))
        }
    }

    // MARK: push

    // https://github.com/phoenixframework/phoenix/blob/a1120f6f292b44ab2ad1b673a937f6aa2e63c225/assets/test/socket_test.js#L413
    func testPushOntoSocket() throws {
        try withSocket { (socket) in
            let expectPushSuccess = self.expectPushSuccess()
            let sub = socket.autoconnect().sink(receiveValue:
                expectAndThen([
                    .open: {
                        socket.push(topic: "phoenix", event: .heartbeat, callback: expectPushSuccess)
                    }
                ])
            )
            defer { sub.cancel() }

            waitForExpectations(timeout: 2)
        }
    }

    // https://github.com/phoenixframework/phoenix/blob/a1120f6f292b44ab2ad1b673a937f6aa2e63c225/assets/test/socket_test.js#L424
    func testPushOntoDisconnectedSocketBuffers() throws {
        try withSocket { (socket) in
            let expectPushSuccess = self.expectPushSuccess()
            socket.push(topic: "phoenix", event: .heartbeat, callback: expectPushSuccess)

            XCTAssertTrue(socket.isClosed)
            XCTAssertEqual(1, socket.pendingPushes.count)
            XCTAssertEqual("phoenix", socket.pendingPushes.first?.topic)
            XCTAssertEqual(PhxEvent.heartbeat, socket.pendingPushes.first?.event)

            socket.connect()

            waitForExpectations(timeout: 2)
        }
    }

    // MARK: heartbeat

    // https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L470
    func testHeartbeatTimeoutMovesSocketToClosedState() throws {
        try withSocket { (socket) in
            let sub = socket.autoconnect().sink(receiveValue:
                expectAndThen([
                    // Attempting to send a heartbeat before the previous one has returned causes the socket to timeout
                    .open: { socket.sendHeartbeat(); socket.sendHeartbeat() },
                    .close: { }
                ])
            )
            defer { sub.cancel() }

            waitForExpectations(timeout: 2)
        }
    }

    // https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L481
    func testPushesHeartbeatWhenConnected() throws {
        try withSocket { (socket) in
            let heartbeatExpectation = self.expectation(description: "Sends heartbeat when connected")

            let sub = socket.autoconnect().sink(receiveValue:
                expectAndThen([
                    .open: { socket.sendHeartbeat { heartbeatExpectation.fulfill(); socket.disconnect() } },
                    .close: { }
                ])
            )
            defer { sub.cancel() }

            waitForExpectations(timeout: 2)
        }
    }

    func testHeartbeatKeepsSocketConnected() throws {
        try withSocket(heartbeatInterval: .milliseconds(100)) { (socket) in
            let closeEx = expectation(description: "Should not have closed")
            closeEx.isInverted = true

            var isActive = true

            let sub = socket
                .autoconnect()
                .receive(on: DispatchQueue.main)
                .sink(receiveValue:
                        onResults([
                            .close: {
                                if isActive {
                                    closeEx.fulfill()
                                }
                            }
                        ])
                )
            defer { sub.cancel() }

            waitForExpectations(timeout: 0.5)
            isActive = false
        }
    }

    func testHeartbeatTimeoutIndirectlyWithWayTooSmallInterval() throws {
        let socket = Socket(url: testHelper.defaultURL, heartbeatInterval: .milliseconds(1))

        let sub = socket.autoconnect().sink(receiveValue: expect(.close))
        defer { sub.cancel() }

        waitForExpectations(timeout: 2)
        socket.disconnectAndWait()
    }

    // https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L491
    func testHeartbeatIsNotSentWhenDisconnected() throws {
        try withSocket { (socket) in
            let noHeartbeatExpectation = self.expectation(description: "Does not send heartbeat when disconnected")
            noHeartbeatExpectation.isInverted = true

            let sub = socket.sink(receiveValue: onResult(.close, noHeartbeatExpectation.fulfill()))
            defer { sub.cancel() }

            socket.sendHeartbeat { noHeartbeatExpectation.fulfill() }

            waitForExpectations(timeout: 0.1)
        }
    }

    // MARK: on open

    // https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L508
    // https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L551
    func testFlushesPushesOnOpen() throws {
        try withSocket { (socket) in
            let receivedResponses = self.expectation(description: "Received response")
            receivedResponses.expectedFulfillmentCount = 2

            socket.push(topic: "unknown", event: .custom("one"))
            socket.push(topic: "unknown", event: .custom("two"))

            let sub = socket.autoconnect().sink { message in
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
    }

    // https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L523
    func testFlushesAllQueuedMessages() throws {
        try withSocket { (socket) in
            let receivedResponses = self.expectation(description: "Received response")
            receivedResponses.expectedFulfillmentCount = 3

            socket.push(topic: "unknown", event: .custom("one"))
            socket.push(topic: "unknown", event: .custom("two"))
            socket.push(topic: "unknown", event: .custom("three"))

            let sub = socket.autoconnect().sink { message in
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
    }

    func testDefaultReconnectTimeInterval() throws {
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
        socket.disconnectAndWait()
    }

    // https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L561
    func testConnectionOpenResetsReconnectTimer() throws {
        try withSocket { (socket) in
            socket.reconnectAttempts = 123

            let sub = socket.autoconnect().sink(receiveValue: expect(.open))
            defer { sub.cancel() }

            waitForExpectations(timeout: 2)

            XCTAssertEqual(0, socket.reconnectAttempts)
        }
    }

    // https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L569
    func testConnectionOpenPublishesOpenMessage() throws {
        try withSocket { (socket) in
            let sub = socket.autoconnect().sink(receiveValue: expect(.open))
            defer { sub.cancel() }

            waitForExpectations(timeout: 2)
        }
    }

    // MARK: socket connection close

    // https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L598
    func testSocketReconnectAfterRemoteClose() throws {
        try withSocket { (socket) in
            socket.reconnectTimeInterval = { _ in .milliseconds(10) }

            let open = self.expectation(description: "Opened multiple times")
            open.assertForOverFulfill = false
            open.expectedFulfillmentCount = 2

            let sub = socket.autoconnect().sink(receiveValue:
                onResults([
                    .open: { open.fulfill(); socket.send("disconnect") }
                ])
            )
            defer { sub.cancel() }

            waitForExpectations(timeout: 2)
        }
    }

    // https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L608
    func testSocketDoesNotReconnectIfExplicitDisconnect() throws {
        try withSocket { (socket) in
            socket.reconnectTimeInterval = { _ in .milliseconds(10) }

            let sub1 = socket.autoconnect().sink(receiveValue:
                expectAndThen([.open: { socket.disconnect() }])
            )
            defer { sub1.cancel() }

            waitForExpectations(timeout: 2)

            let notOpen = self.expectation(description: "Not opened again")
            notOpen.isInverted = true
            let sub2 = socket.sink(receiveValue: onResult(.open, notOpen.fulfill()))
            defer { sub2.cancel() }

            waitForExpectations(timeout: 0.1)
        }
    }

    // https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L618
    func testSocketReconnectAfterRemoteException() throws {
        try withSocket { (socket) in
            socket.reconnectTimeInterval = { _ in .milliseconds(10) }

            let open = self.expectation(description: "Opened multiple times")
            open.assertForOverFulfill = false
            open.expectedFulfillmentCount = 2

            let sub = socket.autoconnect().sink(receiveValue:
                onResults([
                    .open: { open.fulfill(); socket.send("boom") }
                ])
            )
            defer { sub.cancel() }

            waitForExpectations(timeout: 2)
        }
    }

    // https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L628
    func testSocketReconnectsAfterExplicitDisconnectAndThenConnect() throws {
        try withSocket { (socket) in
            socket.reconnectTimeInterval = { _ in .milliseconds(10) }

            let sub1 = socket.autoconnect().sink(receiveValue:
                expectAndThen([
                    .open: { socket.disconnect() },
                    .close: { },
                ])
            )
            waitForExpectations(timeout: 2)
            sub1.cancel()

            let doesNotReconnect = self.expectation(description: "Does not reconnect after disconnect")
            doesNotReconnect.isInverted = true
            let sub2 = socket.sink(receiveValue: onResult(.open, doesNotReconnect.fulfill()))
            waitForExpectations(timeout: 0.1)
            sub2.cancel()

            let reconnects = self.expectation(description: "Reconnects again after explicit connect")
            reconnects.expectedFulfillmentCount = 2
            reconnects.assertForOverFulfill = false
            let sub3 = socket.sink(receiveValue:
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
    }

    // https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L643
    func testRemoteClosePublishesClose() throws {
        try withSocket { (socket) in
            let sub = socket.autoconnect().sink(receiveValue:
                expectAndThen([
                    .open: { socket.send("disconnect") },
                    .close: { },
                ])
            )
            defer { sub.cancel() }

            waitForExpectations(timeout: 2)
        }
    }

    // https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L664
    func testRemoteExceptionErrorsChannels() throws {
        try withSocket { (socket) in
            let channel = socket.join("room:lobby")

            let sub = channel.sink(receiveValue:
                expectAndThen([
                    .join: { socket.send("boom") },
                    .error: { },
                ])
            )
            defer { sub.cancel() }
            socket.connect()

            waitForExpectations(timeout: 2)
        }
    }

    // https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L664
    func testSocketCloseErrorsChannels() throws {
        try withSocket { (socket) in
            let channel = socket.join("room:lobby")

            let sub = channel.sink(receiveValue:
                expectAndThen([
                    .join: { socket.send("disconnect") },
                    .error: { }
                ])
            )
            defer { sub.cancel() }
            socket.connect()

            waitForExpectations(timeout: 2)
        }
    }

    // https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L676
    func testSocketCloseDoesNotErrorChannelsIfLeft() throws {
        try withSocket { (socket) in
            socket.reconnectTimeInterval = { _ in .milliseconds(10) }

            let channel = socket.join("room:lobby")

            let sub1 = channel.sink(receiveValue:
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

            let sub2 = channel.sink(receiveValue: onResult(.error, noError.fulfill()))
            defer { sub2.cancel() }

            socket.send("disconnect")

            waitForExpectations(timeout: 0.1)
        }
    }

    func testRemoteExceptionPublishesError() throws {
        try withSocket { (socket) in
            let errorEx = self.expectation(description: "Should have received error")
            errorEx.assertForOverFulfill = false
            let sub = socket.autoconnect().sink { value in
                switch value {
                case .open:
                    socket.send("boom")
                case .websocketError:
                    errorEx.fulfill()
                case .close:
                    // Whether or not the underlying `WebSocket` publishes an error
                    // is undetermined. Sometimes it will publish an error. Other
                    // times it will just close the connection.
                    errorEx.fulfill()
                default:
                    break
                }
            }
            defer { sub.cancel() }

            waitForExpectations(timeout: 2)
        }
    }

    // MARK: channel messages

    // https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L771
    func testChannelReceivesMessages() throws {
        try withSocket { (socket) in
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
    }

    // https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L788
    func testSocketDecodesAndPublishesMessage() throws {
        try withSocket { (socket) in
            let channel = socket.join("room:lobby")

            let echoEcho = "kapow"
            let echoEx = expectation(description: "Should have received the echo text response")

            let sub = socket.autoconnect().sink { msg in
                guard case .incomingMessage(let message) = msg else { return }
                guard "ok" == message.payload["status"] as? String else { return }
                guard .reply == message.event else { return }
                guard channel.topic == message.topic else { return }
                guard let response = message.payload["response"] as? [String: String] else { return }
                guard echoEcho == response["echo"] else { return }
                echoEx.fulfill()
            }
            defer { sub.cancel() }

            channel.push("echo", payload: ["echo": echoEcho])

            waitForExpectations(timeout: 2)
        }
    }

    func testSocketUsesCustomEncoderAndDecoder() throws {
        let ex = expectation(description: "Received reply from join")

        let encoder: OutgoingMessageEncoder =
            { (message: OutgoingMessage) throws -> RawOutgoingMessage in
                let array: [Any?] = [
                    message.joinRef?.rawValue,
                    message.ref.rawValue,
                    "room:lobbylobbylobby",
                    message.event.stringValue,
                    message.payload
                ]
                return .binary(try JSONSerialization.data(withJSONObject: array, options: []))
            }

        let decoder: IncomingMessageDecoder = { (raw: RawIncomingMessage) throws -> IncomingMessage in
            var decoded = try IncomingMessage(raw)
            XCTAssertEqual("room:lobbylobbylobby", decoded.topic)
            decoded.topic = "notwhatyouexpected"
            return decoded
        }

        try withSocket(encoder: encoder, decoder: decoder) { socket in
            let sub = socket.sink { (message: Socket.Message) in
                switch message {
                case let .incomingMessage(incomingMessage):
                    XCTAssertEqual("notwhatyouexpected", incomingMessage.topic)
                    ex.fulfill()
                default:
                    break
                }
            }
            defer { sub.cancel() }

            let channel = socket.join("room:lobby")
            defer { channel.leave() }
            socket.connect()

            waitForExpectations(timeout: 2)
        }
    }
}

private extension SocketTests {
    func withSocket(
        timeout: DispatchTimeInterval = Socket.defaultTimeout,
        heartbeatInterval: DispatchTimeInterval = Socket.defaultHeartbeatInterval,
        encoder: OutgoingMessageEncoder? = nil,
        decoder: IncomingMessageDecoder? = nil,
        block: (Socket) throws -> Void
    ) throws {
        let socket = Socket(
            url: testHelper.defaultURL,
            timeout: timeout,
            heartbeatInterval: heartbeatInterval,
            customEncoder: encoder,
            customDecoder: decoder
        )
        // We don't want the socket to reconnect unless the test requires it to.
        socket.reconnectTimeInterval = { _ in .seconds(30) }

        try withExtendedLifetime(socket) {
            try block(socket)
            socket.disconnectAndWait()
        }
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
}
