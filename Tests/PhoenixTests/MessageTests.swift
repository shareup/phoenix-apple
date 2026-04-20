import WebSocket
import XCTest

@testable import Phoenix

final class MessageTests: XCTestCase {
    func testDecodeShortMessageThrows() throws {
        XCTAssertThrowsError(
            try Message.decode(.text(#"[null,1,"topic"]"#))
        )
    }
}
