import XCTest
@testable import Phoenix

final class TestHelper {
    let gen = Ref.Generator()
    let userIDGen = Ref.Generator()
    
    var defaultURL: URL { URL(string: "ws://0.0.0.0:4000/socket?user_id=\(userIDGen.advance().rawValue)")! }
    var defaultWebSocketURL: URL { Socket.webSocketURLV2(url: defaultURL) }
    
    func deserialize(_ data: Data) -> [Any?]? {
        return try? JSONSerialization.jsonObject(with: data, options: []) as? [Any?]
    }

    func serialize(_ stuff: [Any?]) -> Data? {
        return try? JSONSerialization.data(withJSONObject: stuff, options: [])
    }
}

extension XCTest {
    func expectation(_ description: String, file: StaticString = #file, line: UInt = #line) -> Expectation {
        return Expectation(description, file: file, line: line)
    }
    
    func wait(for expectations: [Expectation], timeout: TimeInterval, file: StaticString = #file, line: UInt = #line) {
        do {
            try ExpectationHelper.waitWithRunLoopRun(expectations, timeout: timeout)
        } catch ExpectationError.timeout(let expectation) {
            XCTFail("Timeout: \(expectation.description)", file: file, line: line)
            ExpectationHelper.fail(expectation)
        } catch ExpectationError.fulfilledWhenInverted(let expectation) {
            XCTFail("Inverted expectation fulfilled: \(expectation.description)", file: file, line: line)
            ExpectationHelper.fail(expectation)
        } catch ExpectationError.multiple(let expectations) {
            XCTFail("Multiple expectations failed", file: file, line: line)
            expectations.forEach(ExpectationHelper.fail(_:))
        } catch {
            XCTFail("Error: \(error)", file: file, line: line)
        }
    }
    
    func wait(for expectation: Expectation, timeout: TimeInterval, file: StaticString = #file, line: UInt = #line) {
        wait(for: [expectation], timeout: timeout, file: file, line: line)
    }
}

let testHelper = TestHelper()

enum ExpectationError: Error {
    case timeout(Expectation)
    case fulfilledWhenInverted(Expectation)
    case multiple([Expectation])
}

class Expectation {
    let description: String
    var isInverted: Bool = false
    private var _isFullfilled: Bool = false
    
    let file: StaticString
    let line: UInt
    
    var isFulfilled: Bool { _isFullfilled }
    
    init(_ description: String, file: StaticString = #file, line: UInt = #line) {
        self.description = description
        self.file = file
        self.line = line
    }
    
    func fulfill() {
        self._isFullfilled = true
    }
}

enum ExpectationHelper {
    static func fail(_ expectation: Expectation) {
        if expectation.isInverted {
            XCTFail("Fulfilled", file: expectation.file, line: expectation.line)
        } else {
            XCTFail("Timeout", file: expectation.file, line: expectation.line)
        }
    }
    
    static func waitWithRunLoopRun(_ expectations: [Expectation], timeout: TimeInterval) throws {
        let runLoop = RunLoop.current
        let timeoutDate = Date(timeIntervalSinceNow: timeout)
        
        repeat {
            // If all are true, then that means none are inverted and all fulfilled, so return early
            // NOTE: allSatisfy is true for empty arrays
            if try expectations.allSatisfy(handle(_:)) {
                return
            }
            
            runLoop.run(until: Date(timeIntervalSinceNow: 0.01))
            
        } while Date().compare(timeoutDate) == .orderedAscending
        
        // At the end, we haven't thrown for the inverted ones, so remove those and see if the non-inverted are all fulfilled
        
        let filteredExpectations = expectations.filter({ !$0.isInverted })
        
        // NOTE: allSatisfy is true for empty arrays
        if try filteredExpectations.allSatisfy(handle(_:)) {
            return
        } else {
            let failed = expectations.filter({ !(try! handle($0)) })
            
            if failed.count == 1 {
                throw ExpectationError.timeout(failed.first!)
            } else {
                throw ExpectationError.multiple(failed)
            }
        }
    }
    
    static func handle(_ expectation: Expectation) throws -> Bool {
        if expectation.isInverted {
            if expectation.isFulfilled {
                // We can fail early, since we know something has already gone wrong
                throw ExpectationError.fulfilledWhenInverted(expectation)
            } else {
                return false
            }
        } else {
            return expectation.isFulfilled
        }
    }
}
