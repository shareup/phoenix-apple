import XCTest
@testable import Phoenix
import Combine

class SocketTests: XCTestCase {
    func testSocketInit() {
        // https://github.com/phoenixframework/phoenix/blob/b93fa36f040e4d0444df03b6b8d17f4902f4a9d0/assets/test/socket_test.js#L31
        XCTAssertEqual(Socket.defaultTimeout, 10_000)
        
        // https://github.com/phoenixframework/phoenix/blob/b93fa36f040e4d0444df03b6b8d17f4902f4a9d0/assets/test/socket_test.js#L33
        XCTAssertEqual(Socket.defaultHeartbeatInterval, 30_000)
        
        let url: URL = URL(string: "ws://0.0.0.0:4000/socket")!
        let socket = try! Socket(url: url)
        defer { socket.close() }
        
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
        defer { socket.close() }
        
        XCTAssertEqual(socket.timeout, 20_000)
        XCTAssertEqual(socket.heartbeatInterval, 40_000)
    }
    
    func testSocketInitEstablishesConnection() {
        let socket = try! Socket(url: testHelper.defaultURL)
        defer { socket.close() }

        let openMesssageEx = expectation(description: "Should have received an open message")
        let closeMessageEx = expectation(description: "Should have received a close message")
        
        let sub = socket.forever { message in
            switch message {
            case .opened:
                openMesssageEx.fulfill()
            case .closed:
                closeMessageEx.fulfill()
            default:
                break
            }
        }
        defer { sub.cancel() }
        
        wait(for: [openMesssageEx], timeout: 0.5)
        
        socket.close()
        
        wait(for: [closeMessageEx], timeout: 0.5)
    }
    
    func testSocketConnect() {
        let socket = try! Socket(url: testHelper.defaultURL)
        defer { socket.close() }
        
        socket.connect() // calling connect again doesn't blow up
        
        let closeMessageEx = expectation(description: "Should have received a close message")
        let openMesssageEx = expectation(description: "Should have received an open message")
        let reopenMessageEx = expectation(description: "Should have reopened and got an open message")
        
        var openExs = [reopenMessageEx, openMesssageEx]
        
        let sub = socket.forever { message in
            switch message {
            case .opened:
                openExs.popLast()?.fulfill()
            case .closed:
                closeMessageEx.fulfill()
            default:
                break
            }
        }
        defer { sub.cancel() }
        
        wait(for: [openMesssageEx], timeout: 0.5)
        
        socket.close()
        
        wait(for: [closeMessageEx], timeout: 0.5)
        
        socket.connect()
        
        wait(for: [reopenMessageEx], timeout: 0.5)
    }
    
    func testChannelJoin() {
        let openMesssageEx = expectation(description: "Should have received an open message")
        let channelJoinedEx = expectation(description: "Channel joined")
        
        let socket = try! Socket(url: testHelper.defaultURL)
        defer { socket.close() }
        
        let sub = socket.forever {
            if case .opened = $0 { openMesssageEx.fulfill() }
        }
        defer { sub.cancel() }
        
        wait(for: [openMesssageEx], timeout: 0.5)
        
        let channel = socket.join("room:lobby")
        
        let sub2 = channel.forever {
            if case .success(.join) = $0 { channelJoinedEx.fulfill() }
        }
        defer { sub2.cancel() }
        
        wait(for: [channelJoinedEx], timeout: 0.5)
    }
    
    func testSocketReconnect() {
        // special disconnect query item to set a time to auto-disconnect from inside the example server
        let disconnectURL = testHelper.defaultURL.appendingQueryItems(["disconnect": "soon"])
        
        let socket = try! Socket(url: disconnectURL)
        defer { socket.close() }

        let openMesssageEx = expectation(description: "Should have received an open message twice (one after reconnecting)")
        openMesssageEx.expectedFulfillmentCount = 2
        
        let closeMessageEx = expectation(description: "Should have received a close message")
        
        let completeMessageEx = expectation(description: "Should not complete the publishing since it was not closed on purpose")
        completeMessageEx.isInverted = true
        
        let sub = socket.forever(receiveCompletion: { _ in
            completeMessageEx.fulfill()
        }) { message in
            switch message {
            case .opened:
                openMesssageEx.fulfill()
            case .closed:
                closeMessageEx.fulfill()
            default:
                break
            }
        }
        defer { sub.cancel() }
        
        waitForExpectations(timeout: 0.8)
    }
}
