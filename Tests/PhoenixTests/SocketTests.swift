import XCTest
@testable import Phoenix

class SocketTests: XCTestCase {
    let helper = TestHelper()
    
    override func setUp() {
        super.setUp()
        try! helper.bootExample()
    }
    
    override func tearDown() {
        super.tearDown()
        try! helper.quitExample()
    }
    
    func testWebSocketInit() {
        let socket = try! Socket(url: helper.defaultURL)

        let openMesssageEx = expectation(description: "Should have received an open message")
        let closeMessageEx = expectation(description: "Should have received a close message")
        
        let _ = socket.forever { message in
            switch message {
            case .opened:
                openMesssageEx.fulfill()
            case .closed:
                closeMessageEx.fulfill()
            default:
                break
            }
        }
        
        wait(for: [openMesssageEx], timeout: 0.5)
        
        socket.close()
        
        wait(for: [closeMessageEx], timeout: 0.5)
    }
    
    func testChannelJoin() {
        let openMesssageEx = expectation(description: "Should have received an open message")
        let channelJoinedEx = expectation(description: "Channel joined")
        
        let socket = try! Socket(url: helper.defaultURL)
        
        let _ = socket.forever {
            if case .opened = $0 { openMesssageEx.fulfill() }
        }
        
        wait(for: [openMesssageEx], timeout: 0.5)
        
        let channel = socket.join("room:lobby")
        
        let _ = channel.forever {
            if case .success(.join) = $0 { channelJoinedEx.fulfill() }
        }
        
        wait(for: [channelJoinedEx], timeout: 0.5)
    }
    
    func testSocketReconnect() {
        // special disconnect query item to set a time to auto-disconnect from inside the example server
        let disconnectURL = helper.defaultURL.appendingQueryItems(["disconnect": "soon"])
        
        let socket = try! Socket(url: disconnectURL)

        let openMesssageEx = expectation(description: "Should have received an open message")
//        openMesssageEx.expectedFulfillmentCount = 2
        
        let closeMessageEx = expectation(description: "Should have received a close message")
        
        let completeMessageEx = expectation(description: "Should not complete the publishing since it was not closed on purpose")
        completeMessageEx.isInverted = true
        
        let _ = socket.forever(receiveCompletion: { _ in
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
        
        waitForExpectations(timeout: 0.5)
    }
}
