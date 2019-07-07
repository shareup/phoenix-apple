import XCTest
@testable import Phoenix

class SocketTests: XCTestCase {
    var gen = Ref.Generator()
    
    var helper: TestHelper!
    
    override func setUp() {
        super.setUp()
        
        helper = TestHelper()
        
        try! helper.bootExample()
    }
    
    override func tearDown() {
        try! helper.quitExample()
    }
    
    func testWebSocketInit() throws {
        let socket = try Socket(url: helper.deafultURL)
        helper.wait { socket.isOpen }
        XCTAssert(socket.isOpen, "Socket should have been open")
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
