import XCTest

extension XCTestCase {
    @discardableResult
    func expectationWithTest(description: String, test: @escaping @autoclosure () -> Bool) -> XCTestExpectation {
        let expectation = self.expectation(description: description)
        evaluateTest(test, for: expectation)
        return expectation
    }
}

private func evaluateTest(_ test: @escaping () -> Bool, for expectation: XCTestExpectation) {
    DispatchQueue.global().async {
        let didPass = DispatchQueue.main.sync { test() }
        if didPass {
            expectation.fulfill()
        } else {
            evaluateTest(test, for: expectation)
        }
    }
}
