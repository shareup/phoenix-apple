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
        
        helper.wait { socket.isOpen }
        XCTAssert(socket.isOpen, "Socket should have been open")
        
        socket.close()
        helper.wait { socket.isClosed }
        XCTAssert(socket.isClosed, "Socket should have closed")
    }
    
    func testChannelJoin() {
        let socket = try! Socket(url: helper.defaultURL)
        helper.wait { socket.isOpen }
        XCTAssert(socket.isOpen, "Socket should have been open")
        
        let channel = socket.join("room:lobby")
        helper.wait { channel.isJoined }
        XCTAssert(channel.isJoined, "Channel should have been joined")
    }
    
    func testSocketReconnect() {
        // special disconnect query item to set a time to auto-disconnect from inside the example server
        let disconnectURL = helper.defaultURL.appendingQueryItems(["disconnect": "soon"])
        
        let socket = try! Socket(url: disconnectURL)
        helper.wait { socket.isOpen }
        XCTAssert(socket.isOpen, "Socket should have been open")

        let openMesssageEx = XCTestExpectation(description: "Should have received an opened")
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
        
        wait(for: [closeMessageEx], timeout: 0.5)
    }
}
