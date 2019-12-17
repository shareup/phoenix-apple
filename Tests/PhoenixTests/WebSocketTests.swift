import XCTest
@testable import Phoenix
import Forever

class WebSocketTests: XCTestCase {
    var helper = TestHelper()
    
    func testReceiveOpenEvent() throws {
        let webSocket = WebSocket(url: helper.defaultWebSocketURL)
        
        let completeEx = expectation(description: "WebSocket pipeline is complete")
        let openEx = expectation(description: "WebSocket is open")
        
        let sub = webSocket.forever(receiveCompletion: { completion in
            if case .finished = completion {
                completeEx.fulfill()
            }
        }) { result in
            if case .success(.open) = result {
                openEx.fulfill()
            }
        }
        defer { sub.cancel() }
        
        wait(for: [openEx], timeout: 0.25)
        
        webSocket.close()
        
        wait(for: [completeEx], timeout: 0.25)
    }
    
    func testJoinLobby() throws {
        let completeEx = expectation(description: "WebSocket pipeline is complete")
        let openEx = expectation(description: "WebSocket should be open")
        
        let webSocket = WebSocket(url: helper.defaultWebSocketURL)
        
        let sub = webSocket.forever(receiveCompletion: { completion in
            if case .finished = completion {
                completeEx.fulfill()
            }
        }) {
            if case .success(.open) = $0 { return openEx.fulfill() }
        }
        defer { sub.cancel() }
        
        wait(for: [openEx], timeout: 0.5)
        XCTAssert(webSocket.isOpen)
        
        let joinRef = helper.gen.advance().rawValue
        let ref = helper.gen.current.rawValue
        let topic = "room:lobby"
        let event = "phx_join"
        let payload = [String: String]()
        
        let message = helper.serialize([
            joinRef,
            ref,
            topic,
            event,
            payload
        ])!

        webSocket.send(message) { error in
            if let error = error {
                XCTFail("Sending data down the socket failed \(error)")
            }
        }
        
        var hasReplied = false
        let hasRepliedEx = expectation(description: "Should have replied")
        var reply: [Any?] = []
        
        let sub2 = webSocket.forever { result in
            guard !hasReplied else { return }

            let message: WebSocket.Message
            
            hasReplied = true
            
            switch result {
            case .success(let _message):
                message = _message
            case .failure(let error):
                XCTFail("Received an error \(error)")
                return
            }
            
            switch message {
            case .data(_):
                XCTFail("Received a data response, which is wrong")
            case .string(let string):
                reply = self.helper.deserialize(string.data(using: .utf8)!)!
            case .open:
                XCTFail("Received an open event")
            }
            
            hasRepliedEx.fulfill()
        }
        defer { sub2.cancel() }
        
        wait(for: [hasRepliedEx], timeout: 0.5)
        XCTAssert(hasReplied)
        
        if reply.count == 5 {
            XCTAssertEqual(reply[0] as! UInt64, joinRef)
            XCTAssertEqual(reply[1] as! UInt64, ref)
            XCTAssertEqual(reply[2] as! String, "room:lobby")
            XCTAssertEqual(reply[3] as! String, "phx_reply")
            
            let rp = reply[4] as! [String: Any?]
            
            XCTAssertEqual(rp["status"] as! String, "ok")
            XCTAssertEqual(rp["response"] as! [String: String], [:])
        } else {
            XCTFail("Reply wasn't the right shape")
        }
        
        webSocket.close()
        
        wait(for: [completeEx], timeout: 0.5)
        XCTAssert(webSocket.isClosed)
    }
    
    func testEcho() {
        let completeEx = expectation(description: "WebSocket pipeline is complete")
        let openEx = expectation(description: "WebSocket should be open")
        
        let webSocket = WebSocket(url: helper.defaultWebSocketURL)
        
        let sub = webSocket.forever(receiveCompletion: { completion in
            if case .finished = completion {
                completeEx.fulfill()
            }
        }) {
            if case .success(.open) = $0 { return openEx.fulfill() }
        }
        defer { sub.cancel() }
        
        wait(for: [openEx], timeout: 0.5)
        XCTAssert(webSocket.isOpen)

        let joinRef = helper.gen.advance().rawValue
        let ref = helper.gen.current.rawValue
        let topic = "room:lobby"
        let event = "phx_join"
        let payload = [String: String]()
        
        // for later
        let nextRef = self.helper.gen.advance().rawValue

        let message = helper.serialize([
            joinRef,
            ref,
            topic,
            event,
            payload
        ])!

        webSocket.send(message) { error in
            if let error = error {
                XCTFail("Sending data down the socket failed \(error)")
            }
        }

        let repliesEx = expectation(description: "Should receive 6 replies")
        repliesEx.expectedFulfillmentCount = 7
        
        /*
         1.   Channel join response
         2-6. Repeat responses
         7.   Reponse from asking for the repeat to happen
         
         It's possible the response from asking for the repeat to happen could be before, during, or after the repeat messages themselves.
         */
        
        let sub2 = webSocket.forever(receiveCompletion: {
            completion in print("$$$ Websocket publishing complete")
        }) { result in
            let message: WebSocket.Message

            switch result {
            case .success(let _message):
                message = _message
            case .failure(let error):
                XCTFail("Received an error \(error)")
                return
            }

            switch message {
            case .data(_):
                XCTFail("Received a data response, which is wrong")
            case .string(let string):
                let reply = try! IncomingMessage(data: string.data(using: .utf8)!)
                print("reply: \(reply)")
                repliesEx.fulfill()
                
                guard let _joinRef = reply.joinRef else { return }
                guard let _ref = reply.ref else { return }
                
                if _joinRef.rawValue == joinRef && _ref.rawValue == ref {
                    let repeatEvent = "repeat"
                    let repeatPayload: [String: Any] = [
                        "echo": "hello",
                        "amount": 5
                    ]

                    let message = self.helper.serialize([
                        joinRef,
                        nextRef,
                        topic,
                        repeatEvent,
                        repeatPayload
                    ])!

                    webSocket.send(message) { error in
                        if let error = error {
                            XCTFail("Sending data down the socket failed \(error)")
                        }
                    }
                    
                    return
                }
                
                if _joinRef.rawValue == joinRef && _ref.rawValue == nextRef {
                    print("OK, got the response from the repeat trigger message")
                }
            case .open:
                XCTFail("Received an open event")
            }
        }
        defer { sub2.cancel() }
        
        wait(for: [repliesEx], timeout: 0.5)

        webSocket.close()

        wait(for: [completeEx], timeout: 0.5)
        XCTAssert(webSocket.isClosed)
    }
}
