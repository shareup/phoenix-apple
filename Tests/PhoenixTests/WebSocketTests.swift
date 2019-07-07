import XCTest
@testable import Phoenix

class WebSocketTests: XCTestCase {
    var gen = Ref.Generator()
    
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
    
    func testConnectAfterInit() {
        let url = URL(string: "ws://0.0.0.0:4000/socket?user_id=1")!
        
        let webSocket: WebSocket
        
        do {
          webSocket = try WebSocket(url: url)
        } catch {
            return XCTFail()
        }
        
        wait { webSocket.isOpen }
        
        webSocket.close()
        
        wait { webSocket.isClosed }
    }
    
    func testJoinLobby() {
        let url = URL(string: "ws://0.0.0.0:4000/socket?user_id=1")!
        
        let webSocket: WebSocket
        
        do {
            webSocket = try WebSocket(url: url)
        } catch {
            return XCTFail("Making a socket failed \(error)")
        }
        
        wait("Should be open") {
            webSocket.isOpen
        }
        
        let joinRef = gen.advance().rawValue
        let ref = gen.current.rawValue
        let topic = "room:lobby"
        let event = "phx_join"
        let payload: Payload = [:]
        
        let message = serialize([
            joinRef,
            ref,
            topic,
            event,
            payload
        ])!

        try! webSocket.send(.data(message)) { error in
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
                reply = self.deserialize(string.data(using: .utf8)!)!
            @unknown default:
                XCTFail("Received an unknown response type")
            }
        }
        
        wait("Should receive reply") { hasReplied }
        
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
        
        wait("Should be closed") {
            webSocket.isClosed
        }
    }
    
    func testEcho() {
        let url = URL(string: "ws://0.0.0.0:4000/socket?user_id=1")!
        
        let webSocket: WebSocket
        
        do {
            webSocket = try WebSocket(url: url)
        } catch {
            return XCTFail("Making a socket failed \(error)")
        }
        
        wait("Should be open") {
            webSocket.isOpen
        }
        
        let joinRef = gen.advance().rawValue
        let ref = gen.current.rawValue
        let topic = "room:lobby"
        let event = "phx_join"
        let payload: Payload = [:]
        
        let message = serialize([
            joinRef,
            ref,
            topic,
            event,
            payload
        ])!
        
        try! webSocket.send(.data(message)) { error in
            if let error = error {
                XCTFail("Sending data down the socket failed \(error)")
            }
        }
        
        var replies = [IncomingMessage]()
        
        let _ = webSocket.sink { result in
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
                let repeatPayload: Payload = [
                    "echo": "hello",
                    "amount": 5
                ]
                
                let message = self.serialize([
                    joinRef,
                    nextRef,
                    topic,
                    repeatEvent,
                    repeatPayload
                ])!
                
                try! webSocket.send(.data(message)) { error in
                    if let error = error {
                        XCTFail("Sending data down the socket failed \(error)")
                    }
                }
            
            }
            
            return
        }
        
        wait("Should receive reply") { replies.count > 6 }
        
        webSocket.close()
        
        wait("Should be closed") {
            webSocket.isClosed
        }
    }
}

extension WebSocketTests {
    func deserialize(_ data: Data) -> [Any?]? {
        return try? JSONSerialization.jsonObject(with: data, options: []) as? [Any?]
    }
    
    func serialize(_ stuff: [Any?]) -> Data? {
        return try? JSONSerialization.data(withJSONObject: stuff, options: [])
    }
    
    func wait(_ test: () -> Bool) {
        wait("", test: test)
    }
    
    func wait(_ message: String, test: () -> Bool) {
        let start = CFAbsoluteTimeGetCurrent()
        let max = start + 0.2

        while CFAbsoluteTimeGetCurrent() < max {
            if test() {
                return
            } else {
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
            }
        }

        XCTFail(message)
    }
}
