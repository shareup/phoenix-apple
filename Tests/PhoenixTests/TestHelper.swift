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
    
    func expectation(_ description: String) -> Expectation {
        return Expectation(description)
    }
    
    func wait(for expectations: [Expectation], timeout: TimeInterval) throws {
        try ExpectationHelper.waitWithRunLoopRun(expectations, timeout: timeout)
    }
}

extension XCTest {
    func expectation(_ description: String) -> Expectation {
        return testHelper.expectation(description)
    }
    
    func wait(for expectations: [Expectation], timeout: TimeInterval) throws {
        try testHelper.wait(for: expectations, timeout: timeout)
    }
}

let testHelper = TestHelper()

enum ExpectationError: Error {
    case timeout
    case fulfilledWhenInverted
}

struct Expectation {
    let description: String
    var isInverted: Bool = false
    private var _isFullfilled: Bool = false
    
    var isFulfilled: Bool { _isFullfilled }
    
    init(_ description: String) {
        self.description = description
    }
    
    mutating func fulfill() {
        self._isFullfilled = true
    }
}

enum ExpectationHelper {
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
        // NOTE: allSatisfy is true for empty arrays
        if try expectations.filter({ !$0.isInverted }).allSatisfy(handle(_:)) {
            return
        } else {
            throw ExpectationError.timeout
        }
    }
    
    static func handle(_ expectation: Expectation) throws -> Bool {
        if expectation.isInverted {
            if expectation.isFulfilled {
                // We can fail early, since we know something has already gone wrong
                throw ExpectationError.fulfilledWhenInverted
            } else {
                return false
            }
        } else {
            return expectation.isFulfilled
        }
    }
}
