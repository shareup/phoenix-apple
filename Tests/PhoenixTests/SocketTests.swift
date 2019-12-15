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

        let openMesssageEx = XCTestExpectation(description: "Should have received an open message")
        let closeMessageEx = XCTestExpectation(description: "Should have received a close message")
        
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
        let openMesssageEx = XCTestExpectation(description: "Should have received an open message")
        let channelJoinedEx = XCTestExpectation(description: "Channel joined")
        
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

        let openMesssageEx = XCTestExpectation(description: "Should have received an open message")
        let closeMessageEx = XCTestExpectation(description: "Should have received a close message")
        
        let _ = socket.forever { message in
            switch message {
            case .opened:
                openMesssageEx.fulfill()
            case .closed:
                closeMessageEx.fulfill()
            case .incomingMessage(_):
                break
            }
        }
        
        wait(for: [openMesssageEx], timeout: 0.5)
        wait(for: [closeMessageEx], timeout: 0.5)
    }
}
