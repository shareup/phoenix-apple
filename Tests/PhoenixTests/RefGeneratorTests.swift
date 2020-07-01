import XCTest
@testable import Phoenix

class RefGeneratorTests: XCTestCase {
    func testRefGenerator() {
        let generator = Ref.Generator()
        let group = DispatchGroup()

        (0..<100).forEach { _ in
            group.enter()
            DispatchQueue.global().async {
                _ = generator.advance()
                group.leave()
            }
        }

        group.wait()
        XCTAssertEqual(100, generator.current.rawValue)
    }

    // https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L448
    func testRefGeneratorReturnsCurrentAndNextRef() {
        let generator = Ref.Generator()
        XCTAssertEqual(0, generator.current)
        XCTAssertEqual(1, generator.advance())
        XCTAssertEqual(1, generator.current)
    }

    func testRefGeneratorCanStartAnywhere() {
        let generator = Ref.Generator(start: 11)
        XCTAssertEqual(generator.advance(), 12)
    }

    // https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L456
    func testRefGeneratorRestartsForOverflow() {
        // https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Number/MAX_SAFE_INTEGER
        let generator = Ref.Generator(start: 9007199254740991)
        XCTAssertEqual(generator.advance(), 0)
    }
}
