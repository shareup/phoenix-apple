import XCTest

extension XCTestCase {
    func expect<T: RawCaseConvertible>(_ value: T.RawCase) -> (T) -> Void {
        let expectation = self.expectation(description: "Should have received '\(String(describing: value))'")
        return { v in
            if v.matches(value) {
                expectation.fulfill()
            }
        }
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
                expectation.fulfill()
                block()
            }
        }
    }

    func onResult<T: RawCaseConvertible>(_ value: T.RawCase, _ block: @escaping @autoclosure () -> Void) -> (T) -> Void {
        return { v in
            guard v.matches(value) else { return }
            block()
        }
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
