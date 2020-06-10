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
        let socket = Socket(url: testHelper.defaultURL)
        socket.disconnect()
    }

    // https://github.com/phoenixframework/phoenix/blob/14f177a7918d1bc04e867051c4fd011505b22c00/assets/test/socket_test.js#L242
    func testSocketConnectIsNoOp() throws {
        let socket = Socket(url: testHelper.defaultURL)

        socket.connect()
        socket.connect() // calling connect again doesn't blow up
    }


    // https://github.com/phoenixframework/phoenix/blob/14f177a7918d1bc04e867051c4fd011505b22c00/assets/test/socket_test.js#L153
    func testSocketConnectAndDisconnect() throws {
        let socket = Socket(url: testHelper.defaultURL)

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
        let socket = Socket(url: testHelper.defaultURL)
        
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
        let conn = Socket(url: testHelper.defaultURL).autoconnect()
        defer { conn.upstream.disconnect() }

        let sub = conn.forever(receiveValue: expect(.open))
        defer { sub.cancel() }

        waitForExpectations(timeout: 2)
    }
    
    func testSocketAutoconnectSubscriberCancelDisconnects() throws {
        let socket = Socket(url: testHelper.defaultURL)

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
    
    // MARK: Connection state

    // https://github.com/phoenixframework/phoenix/blob/14f177a7918d1bc04e867051c4fd011505b22c00/assets/test/socket_test.js#L309
    func testSocketDefaultsToClosed() throws {
        let socket = Socket(url: testHelper.defaultURL)
        
        XCTAssertEqual(socket.connectionState, "closed")
        XCTAssert(socket.isClosed)
    }

    // https://github.com/phoenixframework/phoenix/blob/14f177a7918d1bc04e867051c4fd011505b22c00/assets/test/socket_test.js#L320
    func testSocketIsConnecting() throws {
        let socket = Socket(url: testHelper.defaultURL)

        let sub = socket.autoconnect().forever(receiveValue:
            expectAndThen([
                .connecting: {
                    XCTAssertEqual(socket.connectionState, "connecting")
                    XCTAssert(socket.isConnecting)
                    XCTAssertFalse(socket.isOpen)
                }
            ])
        )
        defer { sub.cancel() }

        waitForExpectations(timeout: 2)
    }

    // https://github.com/phoenixframework/phoenix/blob/14f177a7918d1bc04e867051c4fd011505b22c00/assets/test/socket_test.js#L328
    func testSocketIsOpen() throws {
        let socket = Socket(url: testHelper.defaultURL)

        let sub = socket.autoconnect().forever(receiveValue:
            expectAndThen([
                .open: {
                    XCTAssertEqual(socket.connectionState, "open")
                    XCTAssert(socket.isOpen)
                }
            ])
        )
        defer { sub.cancel() }

        waitForExpectations(timeout: 2)
    }

    // https://github.com/phoenixframework/phoenix/blob/14f177a7918d1bc04e867051c4fd011505b22c00/assets/test/socket_test.js#L336
    func testSocketIsClosing() throws {
        let socket = Socket(url: testHelper.defaultURL)

        let sub = socket.autoconnect().forever(receiveValue:
            expectAndThen([
                .open: { socket.disconnect() },
                .closing: {
                    XCTAssertEqual(socket.connectionState, "closing")
                    XCTAssert(socket.isClosing)
                    XCTAssertFalse(socket.isOpen)
                }
            ])
        )
        defer { sub.cancel() }

        waitForExpectations(timeout: 2)
    }

    // https://github.com/phoenixframework/phoenix/blob/14f177a7918d1bc04e867051c4fd011505b22c00/assets/test/socket_test.js#L344
    // https://github.com/phoenixframework/phoenix/blob/14f177a7918d1bc04e867051c4fd011505b22c00/assets/test/socket_test.js#L277
    // https://github.com/phoenixframework/phoenix/blob/14f177a7918d1bc04e867051c4fd011505b22c00/assets/test/socket_test.js#L287
    func testSocketIsClosed() throws {
        let socket = Socket(url: testHelper.defaultURL)

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
        let socket = Socket(url: testHelper.defaultURL)

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

        waitForExpectations(timeout: 2)
        XCTAssertEqual(socket.connectionState, "open")
    }

    func testSocketIsDisconnectedAfterAutconnectSubscriptionIsCancelled() throws {
        let socket = Socket(url: testHelper.defaultURL)

        let openEx = expectation(description: "Should have gotten an open message")
        let closeMessageEx = expectation(description: "Should have gotten a closing message")

        var sub: Subscribers.Forever<Publishers.Autoconnect<Socket>>? = nil
        sub = socket.autoconnect().forever(receiveValue:
            onResults([
                .open: { openEx.fulfill(); sub?.cancel() },
                .closing: { closeMessageEx.fulfill() },
            ])
        )

        waitForExpectations(timeout: 2)
    }

    // https://github.com/phoenixframework/phoenix/blob/a1120f6f292b44ab2ad1b673a937f6aa2e63c225/assets/test/socket_test.js#L268
    // https://github.com/phoenixframework/phoenix/blob/14f177a7918d1bc04e867051c4fd011505b22c00/assets/test/socket_test.js#L297
    func testDisconnectTwiceOnlySendsMessagesOnce() throws {
        let socket = Socket(url: testHelper.defaultURL)

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
    
    // MARK: Channel
    
    func testChannelInit() throws {
        let socket = Socket(url: testHelper.defaultURL)
        socket.connect()

        let channel = socket.join("room:lobby")
        defer { channel.leave() }

        let sub = channel.forever(receiveValue: expect(.join))
        defer { sub.cancel() }

        waitForExpectations(timeout: 2.0)
    }

    // https://github.com/phoenixframework/phoenix/blob/a1120f6f292b44ab2ad1b673a937f6aa2e63c225/assets/test/socket_test.js#L360
    func testChannelInitWithParams() throws {
        let socket = Socket(url: testHelper.defaultURL)
        let channel = socket.join("room:lobby", payload: ["success": true])
        
        XCTAssertEqual(channel.topic, "room:lobby")
        XCTAssertEqual(channel.joinPush.payload["success"] as? Bool, true)
    }

    // https://github.com/phoenixframework/phoenix/blob/a1120f6f292b44ab2ad1b673a937f6aa2e63c225/assets/test/socket_test.js#L368
    func testChannelsAreTracked() throws {
        let socket = Socket(url: testHelper.defaultURL)
        let channel1 = socket.join("room:lobby")
        
        XCTAssertEqual(socket.joinedChannels.count, 1)
        
        let channel2 = socket.join("room:lobby2")
        
        XCTAssertEqual(socket.joinedChannels.count, 2)
        
        XCTAssertEqual(channel1.connectionState, "joining")
        XCTAssertEqual(channel2.connectionState, "joining")
    }

    // https://github.com/phoenixframework/phoenix/blob/a1120f6f292b44ab2ad1b673a937f6aa2e63c225/assets/test/socket_test.js#L385
    func testChannelsAreRemoved() throws {
        let socket = Socket(url: testHelper.defaultURL)
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
        let socket = Socket(url: testHelper.defaultURL)

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
        let socket = Socket(url: testHelper.defaultURL)

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
    
    func testHeartbeatTimeoutMovesSocketToClosedState() throws {
        let socket = Socket(url: testHelper.defaultURL)
        defer { socket.disconnect() }

        let sub = socket.autoconnect().forever(receiveValue:
            expectAndThen([
                // Call internal methods to simulate sending heartbeats before the timeout period
                .open: { socket.sendHeartbeat(); socket.sendHeartbeat() },
                .close: { }
            ])
        )
        defer { sub.cancel() }

        waitForExpectations(timeout: 1)
    }
    
    func testHeartbeatTimeoutIndirectlyWithWayTooSmallInterval() throws {
        let socket = Socket(url: testHelper.defaultURL, heartbeatInterval: .milliseconds(1))
        defer { socket.disconnect() }
        
        let closeEx = expectation(description: "Should have closed")
        
        let sub = socket.autoconnect().forever { message in
            switch message {
            case .close:
                closeEx.fulfill()
            default:
                break
            }
        }
        defer { sub.cancel() }
        
        wait(for: [closeEx], timeout: 1)
    }
    
    // MARK: on open
    
    func testFlushesPushesOnOpen() throws {
        let socket = Socket(url: testHelper.defaultURL)
        defer { socket.disconnect() }
        
        let boomEx = expectation(description: "Should have gotten something back from the boom event")
        
        let boom: PhxEvent = .custom("boom")
        
        socket.push(topic: "unknown", event: boom)
        
        let sub = socket.autoconnect().forever { message in
            switch message {
            case .incomingMessage(let incomingMessage):
                Swift.print(incomingMessage)
                
                if incomingMessage.topic == "unknown" && incomingMessage.event == .reply {
                    boomEx.fulfill()
                }
            default:
                break
            }
        }
        defer { sub.cancel() }
        
        waitForExpectations(timeout: 0.5)
    }
    
    // MARK: remote close publishes close
    
    func testRemoteClosePublishesClose() throws {
        let socket = Socket(url: testHelper.defaultURL)
        defer { socket.disconnect() }
        
        assertOpen(socket)
        
        let closeEx = expectation(description: "Should have gotten a close message")
        
        let sub2 = socket.forever {
            if case .close = $0 { closeEx.fulfill() }
        }
        defer { sub2.cancel() }
        
        socket.send("disconnect")
        
        wait(for: [closeEx], timeout: 0.3)
    }
    
    // MARK: remote exception publishes error
    
    func testRemoteExceptionPublishesError() throws {
        let socket = Socket(url: testHelper.defaultURL)
        defer { socket.disconnect() }

        assertOpen(socket)
        
        let errEx = expectation(description: "Should have gotten an error message")
        
        let sub2 = socket.forever {
            if case .websocketError = $0 { errEx.fulfill() }
        }
        defer { sub2.cancel() }
        
        socket.send("boom") { error in
            if error != nil {
                XCTFail()
            }
        }
        
        wait(for: [errEx], timeout: 2)
    }
    
    // MARK: reconnect
    
    func testSocketReconnectAfterRemoteClose() throws {
        let socket = Socket(url: testHelper.defaultURL)
        defer { socket.disconnect() }

        let openMesssageEx = expectation(description: "Should have received an open message twice (one after reconnecting)")
        
        let closeMessageEx = expectation(description: "Should have received a close message")
        
        let completeMessageEx = expectation(description: "Should not complete the publishing since it was not closed on purpose")
        completeMessageEx.isInverted = true
        
        let sub = socket.autoconnect().forever { message in
            switch message {
            case .open:
                openMesssageEx.fulfill()
            case .close:
                closeMessageEx.fulfill()
            default:
                break
            }
        }
        defer { sub.cancel() }
        
        wait(for: [openMesssageEx], timeout: 0.3)
        
        socket.send("disconnect")
        
        wait(for: [closeMessageEx], timeout: 0.3)
        
        sub.cancel()
        
        let reopenMessageEx = expectation(description: "Should have reopened the socket connection")
        
        let sub2 = socket.forever { message in
            switch message {
            case .open:
                reopenMessageEx.fulfill()
            default:
                break
            }
        }
        defer { sub2.cancel() }
        
        waitForExpectations(timeout: 1)
    }
    
    func testSocketReconnectAfterRemoteException() throws {
        let socket = Socket(url: testHelper.defaultURL)
        defer { socket.disconnect() }

        let openMesssageEx = expectation(description: "Should have received an open message twice (one after reconnecting)")
        
        let closeMessageEx = expectation(description: "Should have received a close message")
        
        let completeMessageEx = expectation(description: "Should not complete the publishing since it was not closed on purpose")
        completeMessageEx.isInverted = true
        
        let sub = socket.autoconnect().forever(receiveCompletion: { _ in
            completeMessageEx.fulfill()
        }) { message in
            switch message {
            case .open:
                openMesssageEx.fulfill()
            case .close:
                closeMessageEx.fulfill()
            default:
                break
            }
        }
        defer { sub.cancel() }
        
        wait(for: [openMesssageEx], timeout: 0.3)
        
        socket.send("boom")
        
        wait(for: [closeMessageEx], timeout: 0.3)
        
        sub.cancel()
        
        let reopenMessageEx = expectation(description: "Should have reopened the socket connection")
        
        let sub2 = socket.forever { message in
            switch message {
            case .open:
                reopenMessageEx.fulfill()
            default:
                break
            }
        }
        defer { sub2.cancel() }
        
        waitForExpectations(timeout: 1)
    }
    
    func testSocketDoesNotReconnectIfExplicitDisconnect() throws {
        let socket = Socket(url: testHelper.defaultURL)
        defer { socket.disconnect() }

        let openMesssageEx = expectation(description: "Should have received an open message twice (one after reconnecting)")
        
        let completeMessageEx = expectation(description: "Should not complete the publishing since it was not closed on purpose")
        completeMessageEx.isInverted = true
        
        let sub = socket.autoconnect().forever(receiveCompletion: { _ in
            completeMessageEx.fulfill()
        }) { message in
            switch message {
            case .open:
                openMesssageEx.fulfill()
            default:
                break
            }
        }
        defer { sub.cancel() }
        
        wait(for: [openMesssageEx], timeout: 0.5)
        
        let reopenMessageEx = expectation(description: "Should not have reopened")
        reopenMessageEx.isInverted = true
        
        let closeMessageEx = expectation(description: "Should have received a close message after calling disconnect")
        
        let sub2 = socket.forever { message in
            switch message {
            case .open:
                reopenMessageEx.fulfill()
            case .close:
                closeMessageEx.fulfill()
            default:
                break
            }
        }
        defer { sub2.cancel() }
        
        socket.disconnect()
        
        waitForExpectations(timeout: 1)
    }
    
    func testSocketReconnectAfterExplicitDisconnectAndThenConnect() throws {
        let socket = Socket(url: testHelper.defaultURL)
        defer { socket.disconnect() }

        assertOpen(socket)
        
        let closeMessageEx = expectation(description: "Should have received a close message after calling disconnect")
        
        let sub2 = socket.forever { message in
            switch message {
            case .close:
                closeMessageEx.fulfill()
            default:
                break
            }
        }
        defer { sub2.cancel() }
        
        socket.disconnect()
        
        wait(for: [closeMessageEx], timeout: 0.5)
        
        sub2.cancel()
        
        let reopenMesssageEx = expectation(description: "Should have received an open message after reconnecting")
        let reopenAgainMessageEx = expectation(description: "Should then reconnect again after the server kills the connection becuase of the special command")
        
        var expectations = [reopenMesssageEx, reopenAgainMessageEx]
        
        let sub3 = socket.autoconnect().forever { message in
            switch message {
            case .open:
                let ex = expectations.first!
                ex.fulfill()
                expectations = Array(expectations.dropFirst())
            default:
                break
            }
        }
        defer { sub3.cancel() }
        
        wait(for: [reopenMesssageEx], timeout: 1)
        
        socket.send("disconnect")
        
        waitForExpectations(timeout: 2)
    }
    
    // MARK: how socket close affects channels
    
    func testSocketCloseErrorsChannels() throws {
        let socket = Socket(url: testHelper.defaultURL)
        
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
    
    func testRemoteExceptionErrorsChannels() throws {
        let socket = Socket(url: testHelper.defaultURL)
        
        let channel = socket.join("room:lobby")

        let sub = channel.forever(receiveValue:
            expectAndThen([
                .join: { socket.send("boom") },
                .error: { }
            ])
        )
        defer { sub.cancel() }
        
        socket.connect()

        waitForExpectations(timeout: 2)
    }

    // https://github.com/phoenixframework/phoenix/blob/14f177a7918d1bc04e867051c4fd011505b22c00/assets/test/socket_test.js#L676
    func testSocketCloseDoesNotErrorChannelsIfLeft() throws {
        let socket = Socket(url: testHelper.defaultURL)
        defer { socket.disconnect() }
        
        let channel = socket.join("room:lobby")
        
        assertJoinAndLeave(channel, socket)
        
        let erroredEx = expectation(description: "Channel not should have errored")
        erroredEx.isInverted = true

        let sub2 = channel.forever(receiveValue: onResult(.error, erroredEx.fulfill()))
        defer { sub2.cancel() }
        
        let reconnectedEx = expectation(description: "Socket should have tried to reconnect")

        let sub3 = socket.forever(receiveValue: onResult(.open, reconnectedEx.fulfill()))
        defer { sub3.cancel() }
        
        socket.send("disconnect")
        
        wait(for: [reconnectedEx], timeout: 1)
        
        waitForExpectations(timeout: 1) // give the channel 1 second to error
    }
    
    // MARK: decoding messages
    
    func testSocketDecodesAndPublishesMessage() throws {
        let socket = Socket(url: testHelper.defaultURL)
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
    
    func testChannelReceivesMessages() throws {
        let socket = Socket(url: testHelper.defaultURL)
        defer { socket.disconnect() }
        
        let channel = socket.join("room:lobby")
        let echoEcho = "yahoo"
        let echoEx = expectation(description: "Should have received the echo text response")
        
        channel.push("echo", payload: ["echo": echoEcho]) { result in
            if case .success(let reply) = result,
                reply.isOk,
                reply.response["echo"] as? String == echoEcho {
                
                echoEx.fulfill()
            }
        }
        
        socket.connect()
        
        waitForExpectations(timeout: 1)
    }
}

private extension SocketTests {
    func assertOpen(_ socket: Socket) {
        let openEx = expectation(description: "Should have gotten an open message");

        let sub = socket.forever {
            if case .open = $0 { openEx.fulfill() }
        }
        defer { sub.cancel() }

        socket.connect()

        wait(for: [openEx], timeout: 1)
    }

    func assertJoinAndLeave(_ channel: Channel, _ socket: Socket) {
        let joinedEx = expectation(description: "Channel should have joined")
        let leftEx = expectation(description: "Channel should have left")

        let sub = channel.forever { result in
            switch result {
            case .join:
                joinedEx.fulfill()
                channel.leave()
            case .leave:
                leftEx.fulfill()
            default:
                break
            }
        }
        defer { sub.cancel() }

        socket.connect()

        wait(for: [joinedEx, leftEx], timeout: 1)
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
