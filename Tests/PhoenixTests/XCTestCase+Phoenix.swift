import XCTest
import Combine
import Phoenix

extension XCTestCase {
    func expectFinished<E: Error>() -> (Subscribers.Completion<E>) -> Void {
        let expectation = self.expectation(description: "Should have finished successfully")
        return { completion in
            guard case Subscribers.Completion.finished = completion else { return }
            expectation.fulfill()
        }
    }

    func expectFailure<E>(_ error: E) -> (Subscribers.Completion<E>) -> Void where E: Error, E: Equatable {
        let expectation = self.expectation(description: "Should have failed")
        return { completion in
            guard case Subscribers.Completion.failure(error) = completion else { return }
            expectation.fulfill()
        }
    }
}

extension XCTestCase {
    func expect<T: RawCaseConvertible>(_ value: T.RawCase) -> (T) -> Void {
        return expect([value])
    }
    
    func expect<T: RawCaseConvertible>(_ values: Set<T.RawCase>) -> (T) -> Void {
        let valueToAction = values.reduce(into: [:]) { $0[$1] = { } }
        return expectAndThen(valueToAction)
    }
    
    func expectAndThen<T: RawCaseConvertible>(_ value: T.RawCase, _ block: @escaping @autoclosure () -> Void) -> (T) -> Void {
        return expectAndThen([value: block])
    }

    func expectAndThen<T: RawCaseConvertible>(_ valueToAction: Dictionary<T.RawCase, (() -> Void)>) -> (T) -> Void {
        let valueToExpectation = valueToAction.reduce(into: Dictionary<T.RawCase, XCTestExpectation>())
        { [unowned self] (dict, valueToAction) in
            let key = valueToAction.key
            let expectation = self.expectation(description: "Should have received '\(String(describing: key))'")
            dict[key] = expectation
        }

        return { v in
            let rawCase = v.toRawCase()
            if let block = valueToAction[rawCase], let expectation = valueToExpectation[rawCase] {
                block()
                expectation.fulfill()
            }
        }
    }

    func onResult<T: RawCaseConvertible>(_ value: T.RawCase, _ block: @escaping @autoclosure () -> Void) -> (T) -> Void {
        return onResults([value: block])
    }

    func onResults<T: RawCaseConvertible>(_ valueToAction: Dictionary<T.RawCase, (() -> Void)>) -> (T) -> Void {
        return { v in
            if let block = valueToAction[v.toRawCase()] {
                block()
            }
        }
    }
}

extension XCTestCase {
    func expectOk(response expected: [String: String]? = nil) -> Channel.Callback {
        return _expectReply(isSuccess: true, response: expected)
    }
    
    func expectError(response expected: [String: String]? = nil) -> Channel.Callback {
        return _expectReply(isSuccess: false, response: expected)
    }
    
    func expectFailure(_ error: Channel.Error? = nil) -> Channel.Callback {
        let expectation = self.expectation(description: "Should have received failure")
        return { (result: Result<Channel.Reply, Swift.Error>) -> Void in
            guard case .failure = result else { return }
            if let error = error {
                guard case .failure(let channelError as Channel.Error) = result else { return }
                switch (error, channelError) {
                case (.invalidJoinReply, .invalidJoinReply): expectation.fulfill()
                case (.socketIsClosed, .socketIsClosed): expectation.fulfill()
                case (.lostSocket, .lostSocket): expectation.fulfill()
                case (.noLongerJoining, .noLongerJoining): expectation.fulfill()
                case (.pushTimeout, .pushTimeout): expectation.fulfill()
                case (.joinTimeout, .joinTimeout): expectation.fulfill()
                default: break
                }
            } else {
                expectation.fulfill()
            }
        }
    }
    
    private func _expectReply(isSuccess: Bool, response: [String: String]? = nil) -> Channel.Callback {
        let replyDescription = isSuccess ? "successful" : "error"
        let expectation = self.expectation(description: "Should have received \(replyDescription) response")
        return { (result: Result<Channel.Reply, Swift.Error>) -> Void in
            if case .success(let reply) = result {
                guard reply.isOk == isSuccess else { return }
                if let expected = response {
                    guard let actual = reply.response as? [String: String] else { return }
                    XCTAssertEqual(expected, actual)
                    expectation.fulfill()
                } else {
                    expectation.fulfill()
                }
            }
        }
    }
}

extension XCTestCase {
    func waitForTimeout(_ secondsFromNow: TimeInterval) {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: secondsFromNow))
    }
}

extension XCTestCase {
    @discardableResult
    func expectationWithTest(description: String, test: @escaping @autoclosure () -> Bool) -> XCTestExpectation {
        let expectation = self.expectation(description: description)
        evaluateTest(test, for: expectation)
        return expectation
    }
}

private func evaluateTest(_ test: @escaping () -> Bool, for expectation: XCTestExpectation) {
    testQueue.async {
        let didPass = DispatchQueue.main.sync { test() }
        if didPass {
            expectation.fulfill()
        } else {
            evaluateTest(test, for: expectation)
        }
    }
}

private let testQueue = DispatchQueue(
    label: "app.shareup.phoenix.testqueue",
    qos: .default,
    autoreleaseFrequency: .workItem,
    target: DispatchQueue.global()
)
