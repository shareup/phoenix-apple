import XCTest
@testable import Phoenix
import Combine

class SocketTests: XCTestCase {
    let helper = TestHelper()
    
    func testWebSocketInit() {
        let socket = try! Socket(url: helper.defaultURL)

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
    
    func testChannelJoin() {
        let openMesssageEx = expectation(description: "Should have received an open message")
        let channelJoinedEx = expectation(description: "Channel joined")
        
        let socket = try! Socket(url: helper.defaultURL)
        
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
        let disconnectURL = helper.defaultURL.appendingQueryItems(["disconnect": "soon"])
        
        let socket = try! Socket(url: disconnectURL)

        let openMesssageEx = expectation(description: "Should have received an open message")
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
        
        waitForExpectations(timeout: 0.5)
    }
}
