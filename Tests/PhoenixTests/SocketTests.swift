import XCTest
@testable import Phoenix
import Combine

class SocketTests: XCTestCase {
    // MARK: init, connect, and disconnect
    
    func testSocketInit() {
        // https://github.com/phoenixframework/phoenix/blob/b93fa36f040e4d0444df03b6b8d17f4902f4a9d0/assets/test/socket_test.js#L31
        XCTAssertEqual(Socket.defaultTimeout, 10_000)
        
        // https://github.com/phoenixframework/phoenix/blob/b93fa36f040e4d0444df03b6b8d17f4902f4a9d0/assets/test/socket_test.js#L33
        XCTAssertEqual(Socket.defaultHeartbeatInterval, 30_000)
        
        let url: URL = URL(string: "ws://0.0.0.0:4000/socket")!
        let socket = try! Socket(url: url)
        
        XCTAssertEqual(socket.timeout, Socket.defaultTimeout)
        XCTAssertEqual(socket.heartbeatInterval, Socket.defaultHeartbeatInterval)
        
        XCTAssertEqual(socket.currentRef, 0)
        XCTAssertEqual(socket.url.path, "/socket/websocket")
        XCTAssertEqual(socket.url.query, "vsn=2.0.0")
    }
    
    func testSocketInitOverrides() {
        let socket = try! Socket(
            url: testHelper.defaultURL,
            timeout: 20_000,
            heartbeatInterval: 40_000
        )
        
        XCTAssertEqual(socket.timeout, 20_000)
        XCTAssertEqual(socket.heartbeatInterval, 40_000)
    }
    
    func testSocketInitEstablishesConnection() {
        let socket = try! Socket(url: testHelper.defaultURL)
        defer { socket.disconnect() }

        let openMesssageEx = expectation(description: "Should have received an open message")
        let closeMessageEx = expectation(description: "Should have received a close message")
        
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
    
    func testSocketDisconnectIsNoOp() {
        let socket = try! Socket(url: testHelper.defaultURL)
        socket.disconnect()
    }
    
    func testSocketConnectIsNoOp() {
        let socket = try! Socket(url: testHelper.defaultURL)
        defer { socket.disconnect() }
        
        socket.connect()
        socket.connect() // calling connect again doesn't blow up
    }
    
    func testSocketConnectAndDisconnect() {
        let socket = try! Socket(url: testHelper.defaultURL)
        defer { socket.disconnect() }
        
        let closeMessageEx = expectation(description: "Should have received a close message")
        let openMesssageEx = expectation(description: "Should have received an open message")
        let reopenMessageEx = expectation(description: "Should have reopened and got an open message")
        
        let completeMessageEx = expectation(description: "Should not complete the publishing")
        completeMessageEx.isInverted = true
        
        var openExs = [reopenMessageEx, openMesssageEx]
        
        let sub = socket.forever(receiveCompletion: { _ in
            completeMessageEx.fulfill()
        }) { message in
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
        waitForExpectations(timeout: 0.5)
    }
    
    // MARK: Connection state
    
    func testSocketDefaultsToClosed() {
        let socket = try! Socket(url: testHelper.defaultURL)
        
        XCTAssertEqual(socket.connectionState, "closed")
        XCTAssert(socket.isClosed)
    }
    
    func testSocketIsConnecting() {
        let socket = try! Socket(url: testHelper.defaultURL)
        defer { socket.disconnect() }
        
        let connectingMessageEx = expectation(description: "Should have received a connecting message")
        
        let _ = socket.forever { message in
            switch message {
            case .connecting:
                connectingMessageEx.fulfill()
            default:
                break
            }
        }
        
        socket.connect()
        
        wait(for: [connectingMessageEx], timeout: 0.5)
        
        XCTAssertEqual(socket.connectionState, "connecting")
        XCTAssert(socket.isConnecting)
    }
    
    func testSocketIsOpen() {
        let socket = try! Socket(url: testHelper.defaultURL)
        defer { socket.disconnect() }
        
        let openMessageEx = expectation(description: "Should have received an open message")
        
        let _ = socket.forever { message in
            switch message {
            case .open:
                openMessageEx.fulfill()
            default:
                break
            }
        }
        
        socket.connect()
        
        wait(for: [openMessageEx], timeout: 0.5)
        
        XCTAssertEqual(socket.connectionState, "open")
        XCTAssert(socket.isOpen)
    }
    
    func testSocketIsClosing() {
        let socket = try! Socket(url: testHelper.defaultURL)
        
        let openMessageEx = expectation(description: "Should have received an open message")
        let closingMessageEx = expectation(description: "Should have received a closing message")
        
        let _ = socket.forever { message in
            switch message {
            case .open:
                openMessageEx.fulfill()
            case .closing:
                closingMessageEx.fulfill()
            default:
                break
            }
        }
        
        socket.connect()
        
        wait(for: [openMessageEx], timeout: 0.5)
        
        socket.disconnect()
        
        XCTAssertEqual(socket.connectionState, "closing")
        XCTAssert(socket.isClosing)
        
        wait(for: [closingMessageEx], timeout: 0.1)
    }
    
    // MARK: Channel join
    
    func testChannelInit() {
        let channelJoinedEx = expectation(description: "Should have received join event")
        
        let socket = try! Socket(url: testHelper.defaultURL)
        defer { socket.disconnect() }
        
        socket.connect()
        
        let channel = socket.join("room:lobby")
        defer { channel.leave() }
        
        let sub = channel.forever {
            if case .success(.join) = $0 { channelJoinedEx.fulfill() }
        }
        defer { sub.cancel() }
        
        wait(for: [channelJoinedEx], timeout: 0.5)
    }
    
    func testChannelInitWithParams() {
        let socket = try! Socket(url: testHelper.defaultURL)
        defer { socket.disconnect() }
        
        socket.connect() // TODO: we shouldn't need to connect to init a channel, this is a bug
        
        let channel = socket.join("room:lobby", payload: ["success": true])
        defer { channel.leave() }
        
        XCTAssertEqual(channel.joinPush.payload["success"] as? Bool, true)
    }
    
    // MARK: reconnect
    
    func testSocketReconnect() {
        // special disconnect query item to set a time to auto-disconnect from inside the example server
        let disconnectURL = testHelper.defaultURL.appendingQueryItems(["disconnect": "soon"])
        
        let socket = try! Socket(url: disconnectURL)
        defer { socket.disconnect() }

        let openMesssageEx = expectation(description: "Should have received an open message twice (one after reconnecting)")
        openMesssageEx.expectedFulfillmentCount = 2
        
        let closeMessageEx = expectation(description: "Should have received a close message")
        
        let completeMessageEx = expectation(description: "Should not complete the publishing since it was not closed on purpose")
        completeMessageEx.isInverted = true
        
        let sub = socket.forever(receiveCompletion: { _ in
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
        
        socket.connect()
        
        waitForExpectations(timeout: 1)
    }
}
