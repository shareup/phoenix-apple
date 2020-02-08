import XCTest
import Combine
@testable import Phoenix

class ChannelTests: XCTestCase {
    func testJoinAndLeaveEvents() throws {
        let openMesssageEx = expectation(description: "Should have received an open message")
        
        let socket = try Socket(url: testHelper.defaultURL)
        defer { socket.disconnect() }
        
        let sub = socket.forever {
            if case .open = $0 { openMesssageEx.fulfill() }
        }
        defer { sub.cancel() }
        
        socket.connect()
        
        wait(for: [openMesssageEx], timeout: 0.5)
        
        sub.cancel()
        
        let channelJoinedEx = expectation(description: "Channel joined")
        let channelLeftEx = expectation(description: "Channel left")
        
        let channel = socket.join("room:lobby")
        
        let sub2 = channel.forever { result in
            if case .join = result {
                channelJoinedEx.fulfill()
                return
            }
            
            if case .leave = result {
                channelLeftEx.fulfill()
                return
            }
        }
        defer { sub2.cancel() }
        
        wait(for: [channelJoinedEx], timeout: 0.25)
        
        channel.leave()
        
        waitForExpectations(timeout: 0.25)
    }
    
    func testPushCallback() throws {
        let openMesssageEx = expectation(description: "Should have received an open message")
        
        let socket = try Socket(url: testHelper.defaultURL)
        defer { socket.disconnect() }
        
        let sub = socket.forever {
            if case .open = $0 { openMesssageEx.fulfill() }
        }
        defer { sub.cancel() }
        
        socket.connect()
        
        wait(for: [openMesssageEx], timeout: 0.5)
        
        let channelJoinedEx = expectation(description: "Channel joined")
        
        let channel = socket.join("room:lobby")
        
        let sub2 = channel.forever { result in
            if case .join = result {
                return channelJoinedEx.fulfill()
            }
        }
        defer { sub2.cancel() }
        
        socket.connect()
        
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
        
        let socket = try Socket(url: testHelper.defaultURL)
        defer { socket.disconnect() }
        
        let sub = socket.forever {
            if case .open = $0 { openMesssageEx.fulfill() }
        }
        defer { sub.cancel() }
        
        socket.connect()
        
        wait(for: [openMesssageEx], timeout: 0.5)
        
        let channelJoinedEx = expectation(description: "Channel joined")
        let messageRepeatedEx = expectation(description: "Message repeated correctly")
        let echoText = "This should be repeated"
        
        let channel = socket.join("room:lobby")
        var messageCounter = 0
        
        let sub2 = channel.forever { result in
            if case .join = result {
                return channelJoinedEx.fulfill()
            }
            
            if case .message(let message) = result {
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
        defer { sub2.cancel() }
        
        wait(for: [channelJoinedEx], timeout: 0.25)
        
        let payload: [String: Any] = ["echo": echoText, "amount": 5]
        
        channel.push("repeat", payload: payload)
        
        wait(for: [messageRepeatedEx], timeout: 0.25)
    }
    
    func testMultipleSocketsCollaborating() throws {
        let openMesssageEx1 = expectation(description: "Should have received an open message for socket 1")
        let openMesssageEx2 = expectation(description: "Should have received an open message for socket 2")
        
        let socket1 = try Socket(url: testHelper.defaultURL)
        let socket2 = try Socket(url: testHelper.defaultURL)
        defer {
            socket1.disconnect()
            socket2.disconnect()
        }
        
        let sub1 = socket1.forever { if case .open = $0 { openMesssageEx1.fulfill() } }
        let sub2 = socket2.forever { if case .open = $0 { openMesssageEx2.fulfill() } }
        defer {
            sub1.cancel()
            sub2.cancel()
        }
        
        socket1.connect()
        socket2.connect()
        
        wait(for: [openMesssageEx1, openMesssageEx2], timeout: 0.5)
        
        let channel1 = socket1.join("room:lobby")
        let channel2 = socket2.join("room:lobby")
        
        let messageText = "This should get broadcasted 😎"
        
        let channel1JoinedEx = expectation(description: "Channel 1 joined")
        let channel2JoinedEx = expectation(description: "Channel 2 joined")
        let channel1ReceivedMessageEx = expectation(description: "Channel 1 received the message")
        let channel2ReceivedMessageEx = expectation(description: "Channel 2 received the message which was not right")
        channel2ReceivedMessageEx.isInverted = true
        
        let sub3 = channel1.forever { result in
            if case .join = result {
                return channel1JoinedEx.fulfill()
            }
            
            if case .message(let message) = result {
                let text = message.payload["text"] as? String
                
                if message.event == "message" && text == messageText {
                    return channel1ReceivedMessageEx.fulfill()
                }
            }
        }
        defer { sub3.cancel() }
        
        let sub4 = channel2.forever { result in
            if case .join = result {
                return channel2JoinedEx.fulfill()
            }
            
            if case .message(_) = result {
                return channel2ReceivedMessageEx.fulfill()
            }
        }
        defer { sub4.cancel() }
        
        wait(for: [channel1JoinedEx, channel2JoinedEx], timeout: 0.25)
        
        channel2.push("insert_message", payload: ["text": messageText])
        
        wait(for: [channel1ReceivedMessageEx], timeout: 0.25)
        waitForExpectations(timeout: 0.25)
    }
    
    func testRejoinsAfterDisconnect() throws {
        let disconnectURL = testHelper.defaultURL.appendingQueryItems(["disconnect": "soon"])
        
        let socket = try! Socket(url: disconnectURL)
        defer { socket.disconnect() }
        
        let openMesssageEx = expectation(description: "Should have received an open message twice (once after disconnect)")
        openMesssageEx.expectedFulfillmentCount = 2
        
        let sub = socket.forever {
            if case .open = $0 { openMesssageEx.fulfill(); return }
        }
        defer { sub.cancel() }
        
        socket.connect()
        
        let channelJoinedEx = expectation(description: "Channel should have joined twice (one after disconnecting)")
        channelJoinedEx.expectedFulfillmentCount = 2
        
        let channel = socket.join("room:lobby")
        
        let sub2 = channel.forever {
            if case .join = $0 { channelJoinedEx.fulfill(); return }
        }
        defer { sub2.cancel() }
        
        waitForExpectations(timeout: 1)
    }
    
    func skip_testDoesntRejoinAfterDisconnectIfLeftOnPurpose() throws {
        let disconnectURL = testHelper.defaultURL.appendingQueryItems(["disconnect": "soon"])
        
        let socket = try! Socket(url: disconnectURL)
        defer { socket.disconnect() }
        
        let openMesssageEx = expectation(description: "Should have received an open message twice (once after disconnect)")
        openMesssageEx.expectedFulfillmentCount = 2
        
        let sub = socket.forever {
            if case .open = $0 { openMesssageEx.fulfill(); return }
        }
        defer { sub.cancel() }
        
        socket.connect()
        
        let channelJoinedEx = expectation(description: "Channel should have joined once")
        
        let channel = socket.join("room:lobby")
        
        let sub2 = channel.forever {
            if case .join = $0 { channelJoinedEx.fulfill(); return }
        }
        
        wait(for: [channelJoinedEx], timeout: 0.25)
        
        sub2.cancel()
        
        let channelLeftEx = expectation(description: "Channel should have left once")
        let channelRejoinEx = expectation(description: "Channel should not have rejoined")
        channelRejoinEx.isInverted = true
        
        let sub3 = channel.forever {
            if case .join = $0 { channelRejoinEx.fulfill(); return }
            if case .leave = $0 { channelLeftEx.fulfill(); return }
        }
        defer { sub3.cancel() }
        
        channel.leave()
        
        waitForExpectations(timeout: 1)
    }
}
