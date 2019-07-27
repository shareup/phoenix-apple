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
        let socket = try Socket(url: helper.defaultURL)
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
    
    func testPushCallback() throws {
        let socket = try Socket(url: helper.defaultURL)
        helper.wait { socket.isOpen }
        XCTAssert(socket.isOpen, "Socket should have been open")
        
        let channelJoinedEx = XCTestExpectation(description: "Channel joined")
        
        let channel = socket.join("room:lobby")
        
        let _ = channel.forever { result in
            if case .success(.join) = result {
                return channelJoinedEx.fulfill()
            }
        }
        
        wait(for: [channelJoinedEx], timeout: 0.25)
        
        let repliedOKEx = XCTestExpectation(description: "Received OK reply")
        let repliedErrorEx = XCTestExpectation(description: "Received errro reply")
        
        channel.push("echo", payload: ["echo": "hello"]) { result in
            guard case .success(let reply) = result else {
                XCTFail()
                return
            }

            XCTAssert(reply.isOk, "Reply should have been OK")
            
            let echo = reply.response["echo"] as? String
            
            XCTAssertEqual(echo, "hello")
            
            repliedOKEx.fulfill()
        }
        
        channel.push("echo_error", payload: ["error": "whatever"]) { result in
            guard case .success(let reply) = result else {
                XCTFail()
                return
            }

            XCTAssert(reply.isNotOk, "Reply should have been not OK")
            
            let error = reply.response["error"] as? String
            
            XCTAssertEqual(error, "whatever")
            
            repliedErrorEx.fulfill()
        }
        
        wait(for: [repliedOKEx, repliedErrorEx], timeout: 0.25)
    }
    
    func testReceiveMessages() throws {
        let socket = try Socket(url: helper.defaultURL)
        helper.wait { socket.isOpen }
        XCTAssert(socket.isOpen, "Socket should have been open")
        
        let channelJoinedEx = XCTestExpectation(description: "Channel joined")
        let messageRepeatedEx = XCTestExpectation(description: "Message repeated correctly")
        let echoText = "This should be repeated"
        
        let channel = socket.join("room:lobby")
        var messageCounter = 0
        
        let _ = channel.forever { result in
            if case .success(.join) = result {
                return channelJoinedEx.fulfill()
            }
            
            if case .success(.message(let message)) = result {
                messageCounter += 1
                
                XCTAssertEqual(message.event, "repeated")
                
                let echo = message.payload["echo"] as? String
                XCTAssertEqual(echo, echoText)
                
                if messageCounter >= 5 {
                    messageRepeatedEx.fulfill()
                }
                
                return
            }
        }
        
        wait(for: [channelJoinedEx], timeout: 0.25)
        
        let payload: [String: Any] = ["echo": echoText, "amount": 5]
        
        channel.push("repeat", payload: payload)
        
        wait(for: [messageRepeatedEx], timeout: 0.25)
    }
    
    func testMultipleSocketsCollaborating() throws {
        let socket1 = try Socket(url: helper.defaultURL)
        helper.wait { socket1.isOpen }
        XCTAssert(socket1.isOpen, "Socket should have been open")
        
        let socket2 = try Socket(url: helper.defaultURL)
        helper.wait { socket2.isOpen }
        XCTAssert(socket2.isOpen, "Socket should have been open")
        
        let channel1 = socket1.join("room:lobby")
        let channel2 = socket2.join("room:lobby")
        
        let messageText = "This should get broadcasted 😎"
        
        let channel1JoinedEx = XCTestExpectation(description: "Channel 1 joined")
        let channel2JoinedEx = XCTestExpectation(description: "Channel 2 joined")
        let channel1ReceivedMessageEx = XCTestExpectation(description: "Channel 1 received the message")
        let channel2ReceivedMessageEx = XCTestExpectation(description: "Channel 2 received the message which was not right")
        channel2ReceivedMessageEx.isInverted = true
        
        let _ = channel1.forever { result in
            if case .success(.join) = result {
                return channel1JoinedEx.fulfill()
            }
            
            if case .success(.message(let message)) = result {
                let text = message.payload["text"] as? String
                
                if message.event == "message" && text == messageText {
                    channel1ReceivedMessageEx.fulfill()
                }
                return
            }
        }
        
        let _ = channel2.forever { result in
            if case .success(.join) = result {
                return channel2JoinedEx.fulfill()
            }
            
            if case .success(.message(_)) = result {
                channel2ReceivedMessageEx.fulfill()
            }
        }
        
        wait(for: [channel1JoinedEx, channel2JoinedEx], timeout: 0.25)
        
        channel2.push("insert_message", payload: ["text": messageText])
        
        wait(for: [channel1ReceivedMessageEx], timeout: 0.25)
    }
}
