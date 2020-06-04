import XCTest
@testable import Phoenix
import Combine

class SocketTests: XCTestCase {
    // MARK: init, connect, and disconnect
    
    func testSocketInit() throws {
        // https://github.com/phoenixframework/phoenix/blob/b93fa36f040e4d0444df03b6b8d17f4902f4a9d0/assets/test/socket_test.js#L31
        XCTAssertEqual(Socket.defaultTimeout, .seconds(10))
        
        // https://github.com/phoenixframework/phoenix/blob/b93fa36f040e4d0444df03b6b8d17f4902f4a9d0/assets/test/socket_test.js#L33
        XCTAssertEqual(Socket.defaultHeartbeatInterval, .seconds(30))
        
        let url: URL = URL(string: "ws://0.0.0.0:4000/socket")!
        let socket = Socket(url: url)
        
        XCTAssertEqual(socket.timeout, Socket.defaultTimeout)
        XCTAssertEqual(socket.heartbeatInterval, Socket.defaultHeartbeatInterval)
        
        XCTAssertEqual(socket.currentRef, 0)
        XCTAssertEqual(socket.url.path, "/socket/websocket")
        XCTAssertEqual(socket.url.query, "vsn=2.0.0")
    }
    
    func testSocketInitOverrides() throws {
        let socket = Socket(
            url: testHelper.defaultURL,
            timeout: .seconds(20),
            heartbeatInterval: .seconds(40)
        )
        
        XCTAssertEqual(socket.timeout, .seconds(20))
        XCTAssertEqual(socket.heartbeatInterval, .seconds(40))
    }
    
    func testSocketInitEstablishesConnection() throws {
        let openMesssageEx = expectation(description: "Should have received an open message")
        let closeMessageEx = expectation(description: "Should have received a close message")

        let socket = Socket(url: testHelper.defaultURL)

        let sub = socket.forever { message in
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

        socket.connect()
        
        wait(for: [openMesssageEx], timeout: 0.5)

        socket.disconnect()

        wait(for: [closeMessageEx], timeout: 0.5)
    }
    
    func testSocketDisconnectIsNoOp() throws {
        let socket = Socket(url: testHelper.defaultURL)
        socket.disconnect()
    }
    
    func testSocketConnectIsNoOp() throws {
        let socket = Socket(url: testHelper.defaultURL)
        defer { socket.disconnect() }
        
        socket.connect()
        socket.connect() // calling connect again doesn't blow up
    }
    
    func testSocketConnectAndDisconnect() throws {
        let socket = Socket(url: testHelper.defaultURL)
        defer { socket.disconnect() }
        
        let closeMessageEx = expectation(description: "Should have received a close message")
        let openMesssageEx = expectation(description: "Should have received an open message")
        let reopenMessageEx = expectation(description: "Should have reopened and got an open message")
        
        var openExs = [reopenMessageEx, openMesssageEx]
        
        let sub = socket.forever { message in
            switch message {
            case .open:
                openExs.popLast()?.fulfill()
            case .close:
                closeMessageEx.fulfill()
            default:
                break
            }
        }
        defer { sub.cancel() }
        
        socket.connect()
        
        wait(for: [openMesssageEx], timeout: 0.5)
        
        socket.disconnect()
        
        wait(for: [closeMessageEx], timeout: 0.5)
        
        socket.connect()
        
        wait(for: [reopenMessageEx], timeout: 0.5)
    }
    
    func testSocketAutoconnectHasUpstream() throws {
        let conn = Socket(url: testHelper.defaultURL).autoconnect()
        defer { conn.upstream.disconnect() }
        
        let openMesssageEx = expectation(description: "Should have received an open message")
        
        let sub = conn.forever { message in
            if case .open = message {
                openMesssageEx.fulfill()
            }
        }
        defer { sub.cancel() }
        
        wait(for: [openMesssageEx], timeout: 0.5)
    }
    
    func testSocketAutoconnectSubscriberCancelDisconnects() throws {
        let socket = Socket(url: testHelper.defaultURL)
        defer { socket.disconnect() }
        
        let openMesssageEx = expectation(description: "Should have received an open message")
        let closeMessageEx = expectation(description: "Should have received a close message")
        
        let autoSub = socket.autoconnect().forever { message in
            if case .open = message {
                openMesssageEx.fulfill()
            }
        }
        defer { autoSub.cancel() }
        
        // We cannot detect the close from the autoconnected subscriber because cancelling it will stop receiving messages before the close message arrives
        let sub = socket.forever { message in
            if case .close = message {
                closeMessageEx.fulfill()
            }
        }
        defer { sub.cancel() }
        
        wait(for: [openMesssageEx], timeout: 0.5)
        XCTAssertEqual(socket.connectionState, "open")
        
        autoSub.cancel()
        
        wait(for: [closeMessageEx], timeout: 0.5)
        XCTAssertEqual(socket.connectionState, "closed")
    }
    
    // MARK: Connection state
    
    func testSocketDefaultsToClosed() throws {
        let socket = Socket(url: testHelper.defaultURL)
        
        XCTAssertEqual(socket.connectionState, "closed")
        XCTAssert(socket.isClosed)
    }
    
    func testSocketIsConnecting() throws {
        let socket = Socket(url: testHelper.defaultURL)
        defer { socket.disconnect() }
        
        let connectingMessageEx = expectation(description: "Should have received a connecting message")
        
        let sub = socket.autoconnect().forever { message in
            switch message {
            case .connecting:
                connectingMessageEx.fulfill()
            default:
                break
            }
        }
        defer { sub.cancel() }
        
        wait(for: [connectingMessageEx], timeout: 0.5)
        
        XCTAssertEqual(socket.connectionState, "connecting")
        XCTAssert(socket.isConnecting)
    }
    
    func testSocketIsOpen() throws {
        let socket = Socket(url: testHelper.defaultURL)
        defer { socket.disconnect() }
        
        let openMessageEx = expectation(description: "Should have received an open message")
        
        let sub = socket.autoconnect().forever { message in
            if case .open = message {
                openMessageEx.fulfill()
            }
        }
        defer { sub.cancel() }
        
        wait(for: [openMessageEx], timeout: 0.5)
        
        XCTAssertEqual(socket.connectionState, "open")
        XCTAssert(socket.isOpen)
    }
    
    func testSocketIsClosing() throws {
        let socket = Socket(url: testHelper.defaultURL)
        
        let openMessageEx = expectation(description: "Should have received an open message")
        let closingMessageEx = expectation(description: "Should have received a closing message")
        
        let sub = socket.forever { message in
            switch message {
            case .open:
                openMessageEx.fulfill()
            case .closing:
                closingMessageEx.fulfill()
            default:
                break
            }
        }
        defer { sub.cancel() }
        
        socket.connect()
        
        wait(for: [openMessageEx], timeout: 0.5)
        
        socket.disconnect()
        
        XCTAssertEqual(socket.connectionState, "closing")
        XCTAssert(socket.isClosing)
        
        wait(for: [closingMessageEx], timeout: 0.1)
    }
    
    // MARK: Channel join
    
    func testChannelInit() throws {
        let channelJoinedEx = expectation(description: "Should have received join event")
        
        let socket = Socket(url: testHelper.defaultURL)
        defer { socket.disconnect() }
        
        socket.connect()
        
        let channel = socket.join("room:lobby")
        defer { channel.leave() }
        
        let sub = channel.forever {
            if case .join = $0 { channelJoinedEx.fulfill() }
        }
        defer { sub.cancel() }
        
        wait(for: [channelJoinedEx], timeout: 0.5)
    }
    
    func testChannelInitWithParams() throws {
        let socket = Socket(url: testHelper.defaultURL)
        let channel = socket.join("room:lobby", payload: ["success": true])
        
        XCTAssertEqual(channel.topic, "room:lobby")
        XCTAssertEqual(channel.joinPush.payload["success"] as? Bool, true)
    }
    
    // MARK: track channels
    
    func testChannelsAreTracked() throws {
        let socket = Socket(url: testHelper.defaultURL)
        let _ = socket.join("room:lobby")
        
        XCTAssertEqual(socket.joinedChannels.count, 1)
        
        let _ = socket.join("room:lobby2")
        
        XCTAssertEqual(socket.joinedChannels.count, 2)
    }
    
    // MARK: push
    
    func testPushOntoSocket() throws {
        let socket = Socket(url: testHelper.defaultURL)
        defer { socket.disconnect() }
        
        let openEx = expectation(description: "Should have opened")
        let sentEx = expectation(description: "Should have sent")
        let failedEx = expectation(description: "Shouldn't have failed")
        failedEx.isInverted = true
        
        let sub = socket.autoconnect().forever { message in
            if case .open = message {
                openEx.fulfill()
            }
        }
        defer { sub.cancel() }
        
        wait(for: [openEx], timeout: 0.5)
        
        socket.push(topic: "phoenix", event: .heartbeat, payload: [:]) { error in
            if let error = error {
                print("Couldn't write to socket with error", error)
                failedEx.fulfill()
            } else {
                sentEx.fulfill()
            }
        }
        
        waitForExpectations(timeout: 0.5)
    }
    
    func testPushOntoDisconnectedSocketBuffers() throws {
        let socket = Socket(url: testHelper.defaultURL)
        defer { socket.disconnect() }
        
        let sentEx = expectation(description: "Should have sent")
        let failedEx = expectation(description: "Shouldn't have failed")
        failedEx.isInverted = true
        
        socket.push(topic: "phoenix", event: .heartbeat, payload: [:]) { error in
            if let error = error {
                print("Couldn't write to socket with error", error)
                failedEx.fulfill()
            } else {
                sentEx.fulfill()
            }
        }
        
        DispatchQueue.global().async {
            socket.connect()
        }
        
        waitForExpectations(timeout: 0.5)
    }
    
    // MARK: heartbeat
    
    func testHeartbeatTimeoutMovesSocketToClosedState() throws {
        let socket = Socket(url: testHelper.defaultURL)
        defer { socket.disconnect() }
        
        let openEx = expectation(description: "Should have opened")
        let closeEx = expectation(description: "Should have closed")
        
        let sub = socket.autoconnect().forever { message in
            switch message {
            case .open:
                openEx.fulfill()
            case .close:
                closeEx.fulfill()
            default:
                break
            }
        }
        defer { sub.cancel() }
        
        wait(for: [openEx], timeout: 0.5)
        
        // call internal method to simulate sending the first initial heartbeat
        socket.sendHeartbeat()
        // call internal method to simulate sending a second heartbeat again before the timeout period
        socket.sendHeartbeat()
        
        wait(for: [closeEx], timeout: 0.5)
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
        
        wait(for: [errEx], timeout: 1)
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
        
        waitForExpectations(timeout: 1)
    }
    
    // MARK: how socket close affects channels
    
    func testSocketCloseErrorsChannels() throws {
        let socket = Socket(url: testHelper.defaultURL)
        defer { socket.disconnect() }
        
        let channel = socket.join("room:lobby")
        
        let joinedEx = expectation(description: "Channel should have joined")
        let erroredEx = expectation(description: "Channel should have errored")
        
        let sub = channel.forever { result in
            switch result {
            case .join:
                joinedEx.fulfill()
            case .error:
                erroredEx.fulfill()
            default:
                break
            }
        }
        defer { sub.cancel() }
        
        socket.connect()
        
        wait(for: [joinedEx], timeout: 0.3)
        
        socket.send("disconnect")
        
        waitForExpectations(timeout: 1)
    }
    
    func testRemoteExceptionErrorsChannels() throws {
        let socket = Socket(url: testHelper.defaultURL)
        defer { socket.disconnect() }
        
        let channel = socket.join("room:lobby")
        
        let joinedEx = expectation(description: "Channel should have joined")
        let erroredEx = expectation(description: "Channel should have errored")
        
        let sub = channel.forever { result in
            switch result {
            case .join:
                joinedEx.fulfill()
            case .error:
                erroredEx.fulfill()
            default:
                break
            }
        }
        defer { sub.cancel() }
        
        socket.connect()
        
        wait(for: [joinedEx], timeout: 0.3)
        
        socket.send("boom")
        
        waitForExpectations(timeout: 1)
    }
    
    func testSocketCloseDoesNotErrorChannelsIfLeft() throws {
        let socket = Socket(url: testHelper.defaultURL)
        defer { socket.disconnect() }
        
        let channel = socket.join("room:lobby")
        
        let joinedEx = expectation(description: "Channel should have joined")
        let leftEx = expectation(description: "Channel should have left")
        
        let sub = channel.forever { result in
            switch result {
            case .join:
                joinedEx.fulfill()
            case .leave:
                leftEx.fulfill()
            default:
                break
            }
        }
        defer { sub.cancel() }
        
        socket.connect()
        
        wait(for: [joinedEx], timeout: 1)
        
        channel.leave()
        
        wait(for: [leftEx], timeout: 2)
        
        sub.cancel()
        
        let erroredEx = expectation(description: "Channel not should have errored")
        erroredEx.isInverted = true
        
        let sub2 = channel.forever { result in
            switch result {
            case .error:
                erroredEx.fulfill()
            default:
                break
            }
        }
        defer { sub2.cancel() }
        
        let reconnectedEx = expectation(description: "Socket should have tried to reconnect")
        
        let sub3 = socket.forever { message in
            switch message {
            case .open:
                reconnectedEx.fulfill()
            default:
                break
            }
        }
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
}
