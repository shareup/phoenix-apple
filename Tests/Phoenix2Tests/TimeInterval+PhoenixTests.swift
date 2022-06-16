@testable import Phoenix2
import XCTest

final class TimeIntervalPhoenixTests: XCTestCase {
    func testInitWithNanoseconds() {
        XCTAssertEqual(1.234567890, TimeInterval(nanoseconds: 1_234_567_890))
    }

    func testNanoseconds() {
        XCTAssertEqual(123_456_789, TimeInterval(0.123456789).nanoseconds)
    }
}
