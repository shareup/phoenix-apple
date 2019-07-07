//
//func testHeartbeater() {
//    let url = URL(string: "ws://0.0.0.0:4000/socket?user_id=1")!
//
//    let webSocket: WebSocket
//
//    do {
//        webSocket = try WebSocket(url: url)
//    } catch {
//        return XCTFail("Making a socket failed \(error)")
//    }
//
//    wait("Should be open") { webSocket.isOpen }
//
//    let heartbeater = Heartbeater()
//
//    let publisher = webSocket.compactMap { result -> IncomingMessage? in
//        switch result {
//        case .failure:
//            return nil
//        case .success(let message):
//            switch message {
//            case .data:
//                return nil
//            case .string(let string):
//                if let incomingMessage = try? IncomingMessage(data: string.data(using: .utf8)!) {
//                    return incomingMessage
//                } else {
//                    return nil
//                }
//            @unknown default:
//                fatalError()
//            }
//        }
//        }.filter { message -> Bool in
//            return message.topic == "phoenix"
//    }
//
//    publisher.subscribe(heartbeater)
//
//    wait("Should have subscribed") { heartbeater.isSubscribed }
//
//    try! webSocket.send(.data(heartbeater.pushData(ref: gen.advance().rawValue))) { error in
//        guard let error = error else { return }
//        XCTFail("Sending data down the socket failed \(String(describing: error))")
//    }
//
//    wait("First beat") { heartbeater.count == 1 }
//
//    try! webSocket.send(.data(heartbeater.pushData(ref: gen.advance().rawValue))) { error in
//        guard let error = error else { return }
//        XCTFail("Sending data down the socket failed \(String(describing: error))")
//    }
//
//    wait("Second beat") { heartbeater.count == 2 }
//
//    try! webSocket.send(.data(heartbeater.pushData(ref: gen.advance().rawValue))) { error in
//        guard let error = error else { return }
//        XCTFail("Sending data down the socket failed \(String(describing: error))")
//    }
//
//    wait("Third beat") { heartbeater.count == 3 }
//
//    webSocket.close()
//
//    wait("Should be closed") { webSocket.isClosed }
//}
