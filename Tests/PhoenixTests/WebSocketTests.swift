import XCTest
@testable import Phoenix
import Forever

class WebSocketTests: XCTestCase {
    var gen = Ref.Generator()
    var helper = TestHelper()
    
    var proc: Process? = nil

    override func setUp() {
        super.setUp()
        
        let _proc = Process()
        proc = _proc
        
        _proc.launchPath = "/usr/local/bin/mix"
        _proc.arguments = ["phx.server"]
        
        let PATH = ProcessInfo.processInfo.environment["PATH"]!
        
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "\(PATH):/usr/local/bin/"
        
        _proc.environment = env
        
        _proc.currentDirectoryURL = URL(fileURLWithPath: #file).appendingPathComponent("../example/")
        
        try! _proc.run()
        
        sleep(1)
    }
    
    override func tearDown() {
        super.tearDown()
        
        proc?.interrupt()
        sleep(1)
        proc?.interrupt()
        sleep(1)
        proc?.terminate()
        proc?.waitUntilExit()
    }
    
    func testConnectAfterInit() throws {
        let url = URL(string: "ws://0.0.0.0:4000/socket?user_id=1")!
        
        let webSocket: WebSocket
        
        do {
          webSocket = try WebSocket(url: url)
        } catch {
            return XCTFail()
        }
        
        helper.wait { webSocket.isOpen }
        XCTAssert(webSocket.isOpen)
        
        webSocket.close()
        
        helper.wait { webSocket.isClosed }
        XCTAssert(webSocket.isClosed)
    }
    
    func testJoinLobby() throws {
        let url = URL(string: "ws://0.0.0.0:4000/socket?user_id=1")!
        
        let webSocket: WebSocket
        
        do {
            webSocket = try WebSocket(url: url)
        } catch {
            return XCTFail("Making a socket failed \(error)")
        }
        
        helper.wait { webSocket.isOpen }
        XCTAssert(webSocket.isOpen)
        
        let joinRef = gen.advance().rawValue
        let ref = gen.current.rawValue
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

        webSocket.send(.data(message)) { error in
            if let error = error {
                XCTFail("Sending data down the socket failed \(error)")
            }
        }
        
        var hasReplied = false
        var reply: [Any?] = []
        
        let _ = webSocket.sink { result in
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
            @unknown default:
                XCTFail("Received an unknown response type")
            }
        }
        
        helper.wait { hasReplied }
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
        
        helper.wait { webSocket.isClosed }
        XCTAssert(webSocket.isClosed)
    }
    
    struct RepeatPayload {
        let echo: String
        let amount: UInt64
    }
    
    func testEcho() {
        let url = URL(string: "ws://0.0.0.0:4000/socket?user_id=1")!

        let webSocket: WebSocket

        do {
            webSocket = try WebSocket(url: url)
        } catch {
            return XCTFail("Making a socket failed \(error)")
        }

        helper.wait { webSocket.isOpen }
        XCTAssert(webSocket.isOpen)

        let joinRef = gen.advance().rawValue
        let ref = gen.current.rawValue
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

        webSocket.send(.data(message)) { error in
            if let error = error {
                XCTFail("Sending data down the socket failed \(error)")
            }
        }

        var replies = [IncomingMessage]()
        
        let forever = webSocket.forever(receiveCompletion: {
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
                replies.append(reply)
                print("reply: \(reply)")
            @unknown default:
                XCTFail("Received an unknown response type")
            }

            if replies.count == 1 {
                let nextRef = self.gen.advance().rawValue
                let repeatEvent = "repeat"
                let repeatPayload = RepeatPayload(echo: "hello", amount: 5)

                let message = self.helper.serialize([
                    joinRef,
                    nextRef,
                    topic,
                    repeatEvent,
                    repeatPayload
                ])!

                webSocket.send(.data(message)) { error in
                    if let error = error {
                        XCTFail("Sending data down the socket failed \(error)")
                    }
                }
            }
        }
        
        var hasCancelled = false

        helper.wait {
            if replies.count == 4 && !hasCancelled {
                forever.cancel()
                hasCancelled = true
            }
            
            return replies.count >= 6
        }
        
        XCTAssert(replies.count >= 6, "Only received \(replies.count) replies")

        webSocket.close()

        helper.wait { webSocket.isClosed }
        XCTAssert(webSocket.isClosed)
    }
}
