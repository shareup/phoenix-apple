import XCTest
@testable import Phoenix

class ChannelTests: XCTestCase {
    let helper = TestHelper()
    
    override func setUp() {
        super.setUp()
        try! helper.bootExample()
    }
    
    override func tearDown() {
        super.tearDown()
        try! helper.quitExample()
    }
    
    func testJoinAndLeaveEvents() throws {
        let socket = try Socket(url: helper.deafultURL)
        helper.wait { socket.isOpen }
        XCTAssert(socket.isOpen, "Socket should have been open")
        
        let channelJoinedEx = XCTestExpectation(description: "Channel joined")
        let channelLeftEx = XCTestExpectation(description: "Channel left")
        
        let channelCompletedEx = XCTestExpectation(description: "Channel pipeline completed")
        channelCompletedEx.isInverted = true
        
        let channel = socket.join("room:lobby")
        
        let _ = channel.forever(receiveCompletion: { completion in
            channelCompletedEx.fulfill()
        }) { result in
            if case .success(.join) = result {
                channelJoinedEx.fulfill()
                return
            }
            
            if case .success(.leave) = result {
                channelLeftEx.fulfill()
                return
            }
        }
        
        wait(for: [channelJoinedEx], timeout: 0.25)
        
        channel.leave()
        
        wait(for: [channelLeftEx], timeout: 0.25)
    }
}
