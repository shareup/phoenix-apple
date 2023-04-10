@testable import Phoenix
import XCTest

final class TimeIntervalPhoenixTests: XCTestCase {
    func testInitWithNanoseconds() {
        XCTAssertEqual(0.000000001, TimeInterval(nanoseconds: 1))
        XCTAssertEqual(1.234567890, TimeInterval(nanoseconds: 1_234_567_890))
    }

    func testNanoseconds() {
        XCTAssertEqual(1, TimeInterval(nanoseconds: 1).nanoseconds)
        XCTAssertEqual(123_456_789, TimeInterval(0.123456789).nanoseconds)
        XCTAssertEqual(1, TimeInterval(-0.03281104564666748).nanoseconds)
    }
}
