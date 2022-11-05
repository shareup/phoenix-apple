@testable import Phoenix2
import Synchronized
import XCTest

final class PushBufferTests: XCTestCase {
    func testInitializer() throws {
        XCTAssertFalse(PushBuffer().isActive)
        XCTAssertTrue(PushBuffer(isActive: true).isActive)
    }

    func testIteratesOverAppendedPushes() async throws {
        let pushes = Locked([push1, push2])
        let buffer = PushBuffer(isActive: true)

        Task {
            try await Task.sleep(nanoseconds: NSEC_PER_MSEC * 5)
            try await buffer.append(push1)
        }

        Task {
            try await Task.sleep(nanoseconds: NSEC_PER_MSEC * 10)
            try await buffer.append(push2)
        }

        for try await push in buffer {
            XCTAssertFalse(pushes.access { $0.isEmpty })
            pushes.access { $0.removeAll(where: { $0 == push }) }
            if pushes.access({ $0.isEmpty }) { break }
        }
    }

    func testDoesNotIterateIfInactive() async throws {
        let isActive = Locked(false)
        let buffer = PushBuffer()

        Task { try await buffer.append(push1) }

        Task {
            try await Task.sleep(nanoseconds: NSEC_PER_MSEC * 20)
            isActive.access { $0 = true }
            buffer.start()
        }

        for try await push in buffer {
            XCTAssertTrue(isActive.access { $0 })
            XCTAssertEqual(push1, push)
            break
        }
    }

    func testWaitForSend() async throws {
        let didSend = Locked(false)
        let buffer = PushBuffer(isActive: true)

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await buffer.append(self.push1)
                didSend.access { $0 = true }
            }

            group.addTask {
                for try await push in buffer {
                    XCTAssertFalse(didSend.access { $0 })
                    buffer.didSend(push)
                    break
                }
            }

            try await group.waitForAll()
        }

        XCTAssertTrue(didSend.access { $0 })
    }

    func testWaitForReply() async throws {
        let message = Locked<Message?>(nil)
        let buffer = PushBuffer(isActive: true)

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                let msg = try await buffer.appendAndWait(self.push1)
                message.access { $0 = msg }
            }

            group.addTask {
                for try await push in buffer {
                    buffer.didSend(push)
                    XCTAssertTrue(buffer.didReceive(self.makeReply(for: push)))
                    break
                }
            }

            try await group.waitForAll()
        }

        XCTAssertEqual(makeReply(for: push1), message.access { $0 })
    }

    func testCancellationCancelsIteration() async throws {
        struct State {
            var pushIndex: Int = 0
            var lastPushIndex: Int?
        }

        let state = Locked(State())
        let buffer = PushBuffer(isActive: true)
        let pushStream = makePushStream()

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for await push in pushStream {
                    Swift.print("$$$ PushBuffer.append()", push.id.rawValue)
                    try await buffer.append(push)
                }
            }

            group.addTask {
                for try await push in buffer {
                    state.access { $0.pushIndex = Int(push.id.rawValue) }
                    print("$$$", push.topic, Task.isCancelled)
                    buffer.didSend(push)
                    do { try await Task.sleep(nanoseconds: NSEC_PER_MSEC) }
                    catch {}
                }
            }

            try await Task.sleep(nanoseconds: NSEC_PER_MSEC * 50)

            group.cancelAll()
            state.access { $0.lastPushIndex = $0.pushIndex }
//            try await group.waitForAll()

            state.access {
                XCTAssertEqual($0.pushIndex, $0.lastPushIndex)
            }
        }
    }

    func testCancelAllInFlight() async throws {
        struct TestResult: Equatable {
            var errorCount = 0
            var processCount = 0
        }

        let result = Locked(TestResult())
        let pushes = makePushes(3)
        let buffer = PushBuffer(isActive: true)

        try await withThrowingTaskGroup(of: Void.self) { group in
            pushes.forEach { push in
                group.addTask {
                    do {
                        _ = try await buffer.appendAndWait(push)
                        result.access { $0.processCount += 1 }
                    } catch {
                        result.access { $0.errorCount += 1 }
                    }
                }
            }

            group.addTask {
                var count = 0
                for try await push in buffer {
                    buffer.didSend(push)
                    if count == 0 {
                        buffer.cancelAllInFlight(CancellationError())
                    } else {
                        XCTAssertTrue(buffer.didReceive(self.makeReply(for: push)))
                    }
                    count += 1
                    if count == 3 { return }
                }
            }

            try await group.waitForAll()
        }

        XCTAssertEqual(1, result.access { $0.errorCount })
        XCTAssertEqual(2, result.access { $0.processCount })
    }

    func testSlowPushesDoNotDelayOtherPushes() async throws {
        let pushes = makePushes(5)
        let receivedMessages = Locked<[Message]>([])
        let buffer = PushBuffer(isActive: true)

        try await withThrowingTaskGroup(of: Void.self) { group in
            pushes.forEach { push in
                group.addTask {
                    let message = try await buffer.appendAndWait(push)
                    receivedMessages.access { $0.append(message) }
                }
            }

            group.addTask {
                var count = 0
                for try await push in buffer {
                    count += 1

                    buffer.didSend(push)

                    if push == pushes[0] {
                        Task {
                            try await Task.sleep(nanoseconds: NSEC_PER_MSEC * 50)
                            XCTAssertTrue(buffer.didReceive(self.makeReply(for: push)))
                        }
                    } else {
                        XCTAssertTrue(buffer.didReceive(self.makeReply(for: push)))
                    }

                    if count == 5 { return }
                }
            }

            try await group.waitForAll()
        }

        XCTAssertEqual(5, receivedMessages.access { $0.count })
        XCTAssertEqual(
            makeReply(for: pushes[0]),
            receivedMessages.access { $0.last }
        )
    }
}

private extension PushBufferTests {
    var push1: Push {
        Push(
            joinRef: 1,
            ref: 1,
            topic: "one",
            event: .custom("one"),
            payload: ["one": 1]
        )
    }

    var push2: Push {
        Push(joinRef: nil, ref: 2, topic: "two", event: .join)
    }

    func makePushes(_ count: Int) -> [Push] {
        (1 ... count).map { makePush($0) }
    }

    func makePush(_ id: Int) -> Push {
        Push(
            joinRef: Ref(UInt64(id)),
            ref: Ref(UInt64(id)),
            topic: "\(id)",
            event: .custom("\(id)"),
            payload: ["value": id]
        )
    }

    func makePushStream(maxCount: Int = 1_000) -> AsyncStream<Push> {
        AsyncStream<Push> { cont in
            Task.detached {
                for index in 0 ..< maxCount {
                    cont.yield(self.makePush(index))
                }
                cont.finish()
            }
        }
    }

    func makeReply(for push: Push) -> Message {
        Message(
            joinRef: push.joinRef,
            ref: push.ref,
            topic: push.topic,
            event: .reply,
            payload: push.payload
        )
    }
}
