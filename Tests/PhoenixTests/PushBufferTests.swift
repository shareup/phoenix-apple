import AsyncExtensions
import AsyncTestExtensions
@testable import Phoenix
import Synchronized
import XCTest

final class PushBufferTests: XCTestCase {
    var ref: Locked<Ref>!

    override func setUp() {
        super.setUp()
        ref = Locked(Ref(1))
    }

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

    func testCanWorkThroughMultipleBufferedPushesWaitingForReply() async throws {
        let buffer = PushBuffer()
        buffer.resume()

        let count = Locked(0)
        let expectedCount = 100
        let pushes = makePushes(expectedCount)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for push in pushes {
                group.addTask {
                    self.prepareToSend(push)
                    let msg = try await buffer.appendAndWait(push)
                    XCTAssertEqual(self.makeReply(for: push), msg)
                    count.access { $0 += 1 }
                }
            }

            try await Task.sleep(nanoseconds: NSEC_PER_MSEC * 50)

            group.addTask {
                for try await push in buffer {
                    buffer.didSend(push)
                    XCTAssertTrue(buffer.didReceive(self.makeReply(for: push)))
                }
            }

            await AssertEqualEventually(expectedCount, count.access { $0 })
            group.cancelAll()
        }

        XCTAssertEqual(expectedCount, count.access { $0 })
    }

    // NOTE: This test is hard to follow, but I couldn't think of a better
    // way to write it. The goal of the test is to determine whether or not
    // the order of pushes inside a channel is maintained. Phoenix channels
    // require that the first message pushed to a channel is a `phx_join`
    // message. The rest of the messages should also be sent in the order
    // the Phoenix client (i.e., `PhoenixSocket`) received them. So, this
    // test adds a bunch of messages to `PushBuffer` in different "channels",
    // iterates over them, puts each message back the first time it is seen,
    // and then, the second time it is seen, sends its reply. Also, each time
    // a message is "put back", the queue should move on to the next "channel"
    // to try to send one of its messages. This ensures sync will never get
    // stuck behind a single, badly-behaving channel.
    func testPuttingBackMaintainsTopicSortOrder() async throws {
        let buffer = PushBuffer()
        buffer.resume()

        let expectedCount = 5
        let topics = [1, 2, 3]

        let replies = Locked<[Topic: [Message]]>([:])

        @Sendable
        func append(_ reply: Message) {
            replies.access { replies in
                if var messages = replies[reply.topic] {
                    messages.append(reply)
                    replies[reply.topic] = messages
                } else {
                    replies[reply.topic] = [reply]
                }
            }
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for topic in topics {
                for i in 1 ... expectedCount {
                    group.addTask {
                        let push = self.makePush(i, topic: topic)
                        self.prepareToSend(push)
                        let reply = try! await buffer.appendAndWait(push)
                        append(reply)
                    }
                }
            }

            try await Task.sleep(nanoseconds: NSEC_PER_MSEC * 50)

            group.addTask {
                var count = 0
                var lastReceivedValues = [Topic: Int]()
                var receivedTopics: [Topic] = []
                for try await push in buffer {
                    count += 1

                    receivedTopics.append(push.topic)

                    if let lastValue = lastReceivedValues[push.topic] {
                        XCTAssertEqual(lastValue, self.value(for: push))
                        lastReceivedValues[push.topic] = nil
                        buffer.didSend(push)
                        XCTAssertTrue(buffer.didReceive(self.makeReply(for: push)))
                    } else {
                        lastReceivedValues[push.topic] = self.value(for: push)
                        buffer.putBack(push)
                    }

                    if count == 2 * (topics.count * expectedCount) { break }
                }

                // Check that the topics were always cycled through in the same order
                let topicCycles: [[Topic]] = receivedTopics.reduce(into: []) { acc, topic in
                    if var cycle = acc.popLast(), cycle.count < topics.count {
                        cycle.append(topic)
                        acc.append(cycle)
                    } else {
                        acc.append([topic])
                    }
                }
                XCTAssertTrue(topicCycles.allSatisfy { $0.count == topics.count })
                let firstCycle = topicCycles[0]
                XCTAssertTrue(topicCycles.allSatisfy { $0 == firstCycle })
            }

            try await group.waitForAll()
        }

        XCTAssertTrue(replies.access { replies in
            replies.allSatisfy { $0.value.count == expectedCount }
        })
    }

    func testEmptyTopicsAreRemovedFromNext() async throws {
        let buffer = PushBuffer()
        buffer.resume()

        let topicsAndCounts = [1: 1, 2: 2, 3: 3]

        try await withThrowingTaskGroup(of: Void.self) { group in
            for (topic, count) in topicsAndCounts {
                for i in 1 ... count {
                    group.addTask {
                        let push = self.makePush(i, topic: topic)
                        self.prepareToSend(push)
                        try! await buffer.append(push)
                    }
                }
            }

            try await Task.sleep(nanoseconds: NSEC_PER_MSEC * 50)

            group.addTask {
                var remainingRepliesForTopic = topicsAndCounts.reduce(
                    into: [Topic: Int](),
                    { $0["\($1.key)"] = $1.value }
                )
                var receivedTopics: [Topic] = []

                for try await push in buffer {
                    receivedTopics.append(push.topic)

                    guard let count = remainingRepliesForTopic[push.topic],
                          count > 0
                    else {
                        return XCTFail("Exceeded maximum messages for \(push.topic)")
                    }

                    let remainingCount = count - 1
                    remainingRepliesForTopic[push.topic] = remainingCount == 0
                        ? nil
                        : remainingCount

                    buffer.didSend(push)

                    if remainingRepliesForTopic.isEmpty { break }
                }

                // We would expect to see something like this:
                // `[1, 2, 2, 3, 3, 3]`
                XCTAssertEqual(
                    receivedTopics.sorted(),
                    topicsAndCounts
                        .flatMap { topicAndCount in
                            let (topic, count) = topicAndCount
                            return (0 ..< count).map { _ in "\(topic)" }
                        }
                        .sorted()
                )
            }

            try await group.waitForAll()
        }
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

            try await Task.sleep(nanoseconds: NSEC_PER_MSEC * 10)

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
    func makeRef() -> Ref {
        ref.access { ref in
            let current = ref
            ref = ref.next
            return current
        }
    }

    func makeJoinPush() -> Push {
        Push(topic: "two", event: .join)
    }

    func makePushes(_ count: Int, topic: Int? = nil) -> [Push] {
        (1 ... count).map { makePush($0, topic: topic) }
    }

    func makePush(
        _ id: Int,
        topic: Int? = nil,
        timeout: Date = Date.distantFuture
    ) -> Push {
        let push = Push(
            topic: topic == nil ? "\(id)" : "\(topic!)",
            event: .custom("\(id)"),
            payload: ["value": id],
            timeout: timeout
        )
        return push
    }

    func value(for push: Push) -> Int {
        guard let anyValue = push.payload["value"]?.jsonValue,
              let doubleValue = anyValue as? Double
        else { preconditionFailure() }
        return Int(doubleValue)
    }

    func value(for message: Message) -> Int {
        guard let anyValue = message.payload["value"]?.jsonValue,
              let doubleValue = anyValue as? Double
        else { preconditionFailure() }
        return Int(doubleValue)
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
        let joinRef = UInt64(push.topic)!
        push.prepareToSend(ref: makeRef(), joinRef: Ref(joinRef))
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
