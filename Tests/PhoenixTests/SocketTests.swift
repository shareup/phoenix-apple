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
    
    func testWebSocketInit() throws {
        let socket = try Socket(url: helper.deafultURL)
        
        helper.wait { socket.isOpen }
        XCTAssert(socket.isOpen, "Socket should have been open")
        
        socket.close()
        helper.wait { socket.isClosed }
        XCTAssert(socket.isClosed, "Socket should have closed")
    }
    
    func testChannelJoin() throws {
        let socket = try Socket(url: helper.deafultURL)
        helper.wait { socket.isOpen }
        XCTAssert(socket.isOpen, "Socket should have been open")
        
        let channel = socket.join("room:lobby")
        helper.wait { channel.isJoined }
        XCTAssert(channel.isJoined, "Channel should have been joined")
    }
}
