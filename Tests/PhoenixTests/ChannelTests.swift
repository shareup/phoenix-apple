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
        let openMesssageEx = expectation(description: "Should have received an open message")
        
        let socket = try Socket(url: helper.defaultURL)
        
        let _ = socket.forever {
            if case .opened = $0 { openMesssageEx.fulfill() }
        }
        
        wait(for: [openMesssageEx], timeout: 0.5)
        
        let channelJoinedEx = expectation(description: "Channel joined")
        let channelLeftEx = expectation(description: "Channel left")
        
        let channelCompletedEx = expectation(description: "Channel pipeline should not complete")
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
        waitForExpectations(timeout: 0.25)
    }
    
    func testPushCallback() throws {
        let openMesssageEx = expectation(description: "Should have received an open message")
        
        let socket = try Socket(url: helper.defaultURL)
        
        let _ = socket.forever {
            if case .opened = $0 { openMesssageEx.fulfill() }
        }
        
        wait(for: [openMesssageEx], timeout: 0.5)
        
        let channelJoinedEx = expectation(description: "Channel joined")
        
        let channel = socket.join("room:lobby")
        
        let _ = channel.forever { result in
            if case .success(.join) = result {
                return channelJoinedEx.fulfill()
            }
        }
        
        wait(for: [channelJoinedEx], timeout: 0.25)
        
        let repliedOKEx = expectation(description: "Received OK reply")
        let repliedErrorEx = expectation(description: "Received errro reply")
        
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
        let openMesssageEx = expectation(description: "Should have received an open message")
        
        let socket = try Socket(url: helper.defaultURL)
        
        let _ = socket.forever {
            if case .opened = $0 { openMesssageEx.fulfill() }
        }
        
        wait(for: [openMesssageEx], timeout: 0.5)
        
        let channelJoinedEx = expectation(description: "Channel joined")
        let messageRepeatedEx = expectation(description: "Message repeated correctly")
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
        let openMesssageEx1 = expectation(description: "Should have received an open message for socket 1")
        let openMesssageEx2 = expectation(description: "Should have received an open message for socket 2")
        
        let socket1 = try Socket(url: helper.defaultURL)
        let socket2 = try Socket(url: helper.defaultURL)
        
        let _ = socket1.forever { if case .opened = $0 { openMesssageEx1.fulfill() } }
        let _ = socket2.forever { if case .opened = $0 { openMesssageEx2.fulfill() } }
        
        wait(for: [openMesssageEx1, openMesssageEx2], timeout: 0.5)
        
        let channel1 = socket1.join("room:lobby")
        let channel2 = socket2.join("room:lobby")
        
        let messageText = "This should get broadcasted 😎"
        
        let channel1JoinedEx = expectation(description: "Channel 1 joined")
        let channel2JoinedEx = expectation(description: "Channel 2 joined")
        let channel1ReceivedMessageEx = expectation(description: "Channel 1 received the message")
        let channel2ReceivedMessageEx = expectation(description: "Channel 2 received the message which was not right")
        channel2ReceivedMessageEx.isInverted = true
        
        let _ = channel1.forever { result in
            if case .success(.join) = result {
                return channel1JoinedEx.fulfill()
            }
            
            if case .success(.message(let message)) = result {
                let text = message.payload["text"] as? String
                
                if message.event == "message" && text == messageText {
                    return channel1ReceivedMessageEx.fulfill()
                }
            }
        }
        
        let _ = channel2.forever { result in
            if case .success(.join) = result {
                return channel2JoinedEx.fulfill()
            }
            
            if case .success(.message(_)) = result {
                return channel2ReceivedMessageEx.fulfill()
            }
        }
        
        wait(for: [channel1JoinedEx, channel2JoinedEx], timeout: 0.25)
        
        channel2.push("insert_message", payload: ["text": messageText])
        
        wait(for: [channel1ReceivedMessageEx], timeout: 0.25)
        waitForExpectations(timeout: 0.25)
    }
}
