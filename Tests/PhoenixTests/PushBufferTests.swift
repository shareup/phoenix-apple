import AsyncExtensions
@testable import Phoenix
import Synchronized
import XCTest

final class PushBufferTests: XCTestCase {
    func testInitializer() throws {
        XCTAssertFalse(PushBuffer().isActive)
        XCTAssertTrue(PushBuffer().isIdle)
        XCTAssertFalse(PushBuffer().isTerminal)
    }

    func testIteratesOverAppendedPushes() async throws {
        let push1 = makePush(1)
        let push2 = makePush(2)
        let pushes = Locked([push1, push2])
        let buffer = PushBuffer()
        buffer.resume()

        Task {
            try await Task.sleep(nanoseconds: NSEC_PER_MSEC * 5)
            try await buffer.append(push1) as Void
        }

        Task {
            try await Task.sleep(nanoseconds: NSEC_PER_MSEC * 10)
            try await buffer.append(push2) as Void
        }

        for try await push in buffer {
            XCTAssertFalse(pushes.access { $0.isEmpty })
            pushes.access { $0.removeAll(where: { $0 == push }) }
            if pushes.access({ $0.isEmpty }) { break }
        }
    }

    func testDoesNotIterateIfInactive() async throws {
        let push = makePush(1)

        let isActive = Locked(false)
        let buffer = PushBuffer()

        Task { try await buffer.append(push) }

        Task {
            try await Task.sleep(nanoseconds: NSEC_PER_MSEC * 20)
            isActive.access { $0 = true }
            buffer.resume()
        }

        for try await p in buffer {
            XCTAssertTrue(isActive.access { $0 })
            XCTAssertEqual(push, p)
            break
        }
    }

    func testWaitForSend() async throws {
        let push = makePush(1)
        let didSend = Locked(false)
        let buffer = PushBuffer()
        buffer.resume()

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await buffer.append(push)
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

    func testCancelNext() async throws {
        let didCancel = Locked(false)

        let buffer = PushBuffer()
        buffer.resume()

        let nextTask = Task {
            do {
                for try await _ in buffer {
                    XCTFail("Should not have produced push")
                }
            } catch {
                didCancel.access { $0 = true }
            }
        }

        Task {
            try await Task.sleep(nanoseconds: NSEC_PER_MSEC * 50)
            nextTask.cancel()
        }

        await nextTask.value

        XCTAssertTrue(didCancel.access { $0 })
    }

    func testTimeOutAppendedPush() async throws {
        let buffer = PushBuffer()
        buffer.resume()

        let push1 = makePush(1, timeout: Date(timeIntervalSinceNow: 0.01))

        let pushTask = Task {
            do {
                prepareToSend(push1)
                try await buffer.append(push1)
                XCTFail("Should not have sent push")
            } catch {
                XCTAssertTrue(error is TimeoutError)
            }
        }

        await pushTask.value
    }

    func testTimeOutAppendedAndWaitedPush() async throws {
        let buffer = PushBuffer()
        buffer.resume()

        let push1 = makePush(1, timeout: Date(timeIntervalSinceNow: 0.01))

        let pushTask = Task {
            do {
                prepareToSend(push1)
                let reply = try await buffer.appendAndWait(push1)
                XCTFail("Should not have received a reply: \(reply)")
            } catch {
                XCTAssertTrue(error is TimeoutError)
            }
        }

        await pushTask.value
    }

    func testEarlierTimeoutOverridesLaterTimeout() async throws {
        let didTimeout = Locked(false)
        let replyFut = Future<Message>()

        let buffer = PushBuffer()
        buffer.resume()

        let push1 = makePush(1)
        let push2 = makePush(2, timeout: Date(timeIntervalSinceNow: 0.01))

        Task {
            prepareToSend(push1)
            replyFut.resolve(try await buffer.appendAndWait(push1))
        }

        let timeoutTask = Task {
            do {
                prepareToSend(push2)
                _ = try await buffer.appendAndWait(push2)
            } catch is TimeoutError {
                didTimeout.access { $0 = true }
            } catch {
                XCTFail("Should have received TimeoutError, not \(error)")
            }
        }

        Task {
            for try await push in buffer {
                buffer.didSend(push)
                if push == push1 { break }
            }

            await timeoutTask.value
            XCTAssertTrue(buffer.didReceive(makeReply(for: push1)))
        }

        let reply = try await replyFut.value
        XCTAssertEqual(reply.joinRef, push1.joinRef)
        XCTAssertEqual(reply.ref, push1.ref)
        XCTAssertTrue(didTimeout.access { $0 })
    }

    func testReschedulesTimeoutAfterTimeoutFires() async throws {
        let timeoutIDs = Locked([Int]())
        let ex = expectation(description: "Should have timed out twice")

        let buffer = PushBuffer()
        buffer.resume()

        let push1 = makePush(1, timeout: Date(timeIntervalSinceNow: 0.01))
        let push2 = makePush(2, timeout: Date(timeIntervalSinceNow: 0.02))

        @Sendable
        func timeoutTask(push: Push) -> Task<Void, Never> {
            Task {
                do {
                    prepareToSend(push)
                    _ = try await buffer.appendAndWait(push)
                } catch is TimeoutError {
                    let count = timeoutIDs.access { timeoutIDs in
                        timeoutIDs.append(Int(push.topic)!)
                        return timeoutIDs.count
                    }
                    if count > 1 { ex.fulfill() }
                } catch {
                    XCTFail("Should have received TimeoutError, not \(error)")
                }
            }
        }

        let _ = await timeoutTask(push: push1).value
        let _ = await timeoutTask(push: push2).value

        #if compiler(>=5.8)
            await fulfillment(of: [ex], timeout: 2)
        #else
            wait(for: expectations, timeout: 2)
        #endif

        XCTAssertEqual([1, 2], timeoutIDs.access { $0 })
    }

    func testFailAppendedPush() async throws {
        struct Err: Error {}

        let buffer = PushBuffer()
        buffer.resume()

        let push = makePush(1)

        let pushTask = Task {
            do {
                prepareToSend(push)
                try await buffer.append(push)
                XCTFail("Should not have sent push")
            } catch {
                XCTAssertTrue(error is Err)
            }
        }

        Task {
            buffer.didFail(push, error: Err())
        }

        await pushTask.value
    }

    func testFailAppendedAndWaitedPush() async throws {
        struct Err: Error {}

        let buffer = PushBuffer()
        buffer.resume()

        let push = makePush(1)

        let pushTask = Task {
            do {
                prepareToSend(push)
                let reply = try await buffer.appendAndWait(push)
                XCTFail("Should not have received \(reply)")
            } catch {
                XCTAssertTrue(error is Err)
            }
        }

        Task {
            for try await p in buffer {
                XCTAssertTrue(buffer.didFail(p, error: Err()))
                break
            }
        }

        await pushTask.value
    }

    func testWaitForMultipleSends() async throws {
        let buffer = PushBuffer()
        buffer.resume()

        let count = Locked(0)
        let expectedCount = 1000
        let stream = makePushStream(maxCount: expectedCount)

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for await push in stream {
                    try await buffer.append(push)
                    count.access { $0 += 1 }
                }
            }

            group.addTask {
                for try await push in buffer {
                    buffer.didSend(push)
                }
            }

            try await group.next()
            group.cancelAll()
        }

        XCTAssertEqual(expectedCount, count.access { $0 })
    }

    func testWaitForReply() async throws {
        let push = makePush(1)

        let message = Locked<Message?>(nil)
        let buffer = PushBuffer()
        buffer.resume()

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                self.prepareToSend(push)
                let msg = try await buffer.appendAndWait(push)
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

        XCTAssertEqual(makeReply(for: push), message.access { $0 })
    }

    func testWaitForMultipleReplies() async throws {
        let buffer = PushBuffer()
        buffer.resume()

        let count = Locked(0)
        let expectedCount = 1000
        let stream = makePushStream(maxCount: expectedCount)

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for await push in stream {
                    self.prepareToSend(push)
                    let msg = try await buffer.appendAndWait(push)
                    XCTAssertEqual(self.makeReply(for: push), msg)
                    count.access { $0 += 1 }
                }
            }

            group.addTask {
                for try await push in buffer {
                    buffer.didSend(push)
                    XCTAssertTrue(buffer.didReceive(self.makeReply(for: push)))
                }
            }

            try await group.next()
            group.cancelAll()
        }

        XCTAssertEqual(expectedCount, count.access { $0 })
    }

    func testCancellationCancelsIteration() async throws {
        struct State {
            var pushIndex: Int = 0
            var lastPushIndex: Int?
        }

        let state = Locked(State())
        let buffer = PushBuffer()
        buffer.resume()
        let pushStream = makePushStream()

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                do {
                    for await push in pushStream {
                        self.prepareToSend(push)
                        try await buffer.append(push)
                    }
                } catch {
                    XCTAssertTrue(error is CancellationError)
                }
            }

            group.addTask {
                do {
                    for try await push in buffer {
                        state.access { $0.pushIndex = Int(push.ref!.rawValue) }
                        buffer.didSend(push)
                    }
                } catch {
                    XCTAssertTrue(error is CancellationError)
                }
            }

            try await Task.sleep(nanoseconds: NSEC_PER_MSEC * 50)

            group.cancelAll()

            // Save the current push index and, after `waitForAll()`
            // finishes, verify that nothing else has been processed.
            state.access { $0.lastPushIndex = $0.pushIndex }

            try await group.waitForAll()

            state.access { state in
                // It's possible for the push to have been sent before the
                // cancellation was received by the tasks, which means the
                // buffer.next() could have been called once more after
                // lastPushIndex was saved.
                let diff = state.pushIndex - state.lastPushIndex!
                XCTAssertTrue(diff == 0 || diff == 1)
            }
        }
    }

    func testPause() async throws {
        struct TestResult: Equatable {
            var errorCount = 0
            var processCount = 0
        }

        let result = Locked(TestResult())
        let pushes = makePushes(3)
        let buffer = PushBuffer()
        buffer.resume()

        try await withThrowingTaskGroup(of: Void.self) { group in
            pushes.forEach { push in
                group.addTask {
                    do {
                        self.prepareToSend(push)
                        _ = try await buffer.appendAndWait(push)
                        result.access { $0.processCount += 1 }
                    } catch {
                        XCTAssertTrue(error is CancellationError)
                        result.access { $0.errorCount += 1 }
                    }
                }
            }

            group.addTask {
                var iterator = buffer.makeAsyncIterator()

                let first = try await iterator.next()!
                buffer.didSend(first)

                let second = try await iterator.next()!
                buffer.didSend(second)

                buffer.pause()

                let didResume = Locked(false)
                Task {
                    try await Task.sleep(nanoseconds: NSEC_PER_MSEC * 20)
                    didResume.access { $0 = true }
                    buffer.resume()
                }

                let third = try await iterator.next()!
                XCTAssertTrue(didResume.access { $0 })

                buffer.didSend(third)
                XCTAssertTrue(buffer.didReceive(self.makeReply(for: third)))
            }

            try await group.waitForAll()
        }

        XCTAssertEqual(2, result.access { $0.errorCount })
        XCTAssertEqual(1, result.access { $0.processCount })
    }

    func testPauseWithCustomError() async throws {
        struct TestResult: Equatable {
            var errorCount = 0
            var processCount = 0
        }

        struct TestError: Error {}

        let result = Locked(TestResult())
        let pushes = makePushes(3)
        let buffer = PushBuffer()
        buffer.resume()

        try await withThrowingTaskGroup(of: Void.self) { group in
            pushes.forEach { push in
                group.addTask {
                    do {
                        self.prepareToSend(push)
                        _ = try await buffer.appendAndWait(push)
                        result.access { $0.processCount += 1 }
                    } catch {
                        XCTAssertTrue(error is TestError)
                        result.access { $0.errorCount += 1 }
                    }
                }
            }

            group.addTask {
                var iterator = buffer.makeAsyncIterator()

                let first = try await iterator.next()!
                buffer.didSend(first)

                let second = try await iterator.next()!
                buffer.didSend(second)

                buffer.pause(error: TestError())

                let didResume = Locked(false)
                Task {
                    try await Task.sleep(nanoseconds: NSEC_PER_MSEC * 20)
                    didResume.access { $0 = true }
                    buffer.resume()
                }

                let third = try await iterator.next()!
                XCTAssertTrue(didResume.access { $0 })

                buffer.didSend(third)
                XCTAssertTrue(buffer.didReceive(self.makeReply(for: third)))
            }

            try await group.waitForAll()
        }

        XCTAssertEqual(2, result.access { $0.errorCount })
        XCTAssertEqual(1, result.access { $0.processCount })
    }

    func testCancelAndInvalidate() async throws {
        struct TestResult: Equatable {
            var errorCount = 0
            var processCount = 0
        }

        let result = Locked(TestResult())
        let pushes = makePushes(4)
        let buffer = PushBuffer()
        buffer.resume()

        try await withThrowingTaskGroup(of: Void.self) { group in
            pushes.forEach { push in
                group.addTask {
                    do {
                        self.prepareToSend(push)
                        _ = try await buffer.appendAndWait(push)
                        result.access { $0.processCount += 1 }
                    } catch {
                        XCTAssertTrue(error is CancellationError)
                        result.access { $0.errorCount += 1 }
                    }
                }
            }

            group.addTask {
                var iterator = buffer.makeAsyncIterator()

                let first = try await iterator.next()!
                buffer.didSend(first)
                XCTAssertTrue(buffer.didReceive(self.makeReply(for: first)))

                let second = try await iterator.next()!
                buffer.didSend(second)

                let third = try await iterator.next()!
                buffer.didSend(third)

                buffer.cancelAllAndInvalidate()

                XCTAssertNoThrow(buffer.resume())

                do {
                    _ = try await iterator.next()!
                    XCTFail("Should have thrown CancellationError")
                } catch {
                    XCTAssertTrue(error is CancellationError)
                }

                XCTAssertNoThrow(buffer.didSend(pushes[3]))
                XCTAssertFalse(buffer.didReceive(self.makeReply(for: pushes[3])))
            }

            try await group.waitForAll()
        }

        XCTAssertEqual(3, result.access { $0.errorCount })
        XCTAssertEqual(1, result.access { $0.processCount })
    }

    func testCancelAndInvalidateWithCustomError() async throws {
        struct TestResult: Equatable {
            var errorCount = 0
            var processCount = 0
        }

        struct TestError: Error {}

        let result = Locked(TestResult())
        let pushes = makePushes(4)
        let buffer = PushBuffer()
        buffer.resume()

        try await withThrowingTaskGroup(of: Void.self) { group in
            pushes.forEach { push in
                group.addTask {
                    do {
                        self.prepareToSend(push)
                        _ = try await buffer.appendAndWait(push)
                        result.access { $0.processCount += 1 }
                    } catch {
                        XCTAssertTrue(error is TestError)
                        result.access { $0.errorCount += 1 }
                    }
                }
            }

            group.addTask {
                var iterator = buffer.makeAsyncIterator()

                let first = try await iterator.next()!
                buffer.didSend(first)
                XCTAssertTrue(buffer.didReceive(self.makeReply(for: first)))

                let second = try await iterator.next()!
                buffer.didSend(second)

                let third = try await iterator.next()!
                buffer.didSend(third)

                buffer.cancelAllAndInvalidate(error: TestError())

                XCTAssertNoThrow(buffer.resume())

                do {
                    _ = try await iterator.next()!
                    XCTFail("Should have thrown TestError")
                } catch {
                    XCTAssertTrue(error is TestError)
                }

                XCTAssertNoThrow(buffer.didSend(pushes[3]))
                XCTAssertFalse(buffer.didReceive(self.makeReply(for: pushes[3])))
            }

            try await group.waitForAll()
        }

        XCTAssertEqual(3, result.access { $0.errorCount })
        XCTAssertEqual(1, result.access { $0.processCount })
    }

    func testSlowPushesDoNotDelayOtherPushes() async throws {
        let pushes = makePushes(5)
        let receivedMessages = Locked<[Message]>([])
        let buffer = PushBuffer()
        buffer.resume()

        try await withThrowingTaskGroup(of: Void.self) { group in
            pushes.forEach { push in
                group.addTask {
                    self.prepareToSend(push)
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

                // Assert that the buffer has been emptied even though the
                // the messages haven't all been processed yet.
                XCTAssertTrue(count == 5 && receivedMessages.access { $0.count } < 5)
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
    func makeJoinPush() -> Push {
        Push(topic: "two", event: .join)
    }

    func makePushes(_ count: Int) -> [Push] {
        (1 ... count).map { makePush($0) }
    }

    func makePush(
        _ id: Int,
        timeout: Date = Date.distantFuture
    ) -> Push {
        let push = Push(
            topic: "\(id)",
            event: .custom("\(id)"),
            payload: ["value": id],
            timeout: timeout
        )
        return push
    }

    func makePushStream(maxCount: Int = 1000) -> AsyncStream<Push> {
        AsyncStream<Push> { cont in
            for index in 0 ..< maxCount {
                cont.yield(self.makePush(index))
            }
            cont.finish()
        }
    }

    func prepareToSend(_ push: Push) {
        assert(push.joinRef == nil)
        assert(push.ref == nil)
        let i = UInt64(push.topic)!
        push.prepareToSend(ref: Ref(i), joinRef: Ref(i))
    }

    func makeReply(for push: Push) -> Message {
        assert(push.joinRef != nil)
        assert(push.ref != nil)
        return Message(
            joinRef: push.joinRef,
            ref: push.ref,
            topic: push.topic,
            event: .reply,
            payload: push.payload
        )
    }
}
