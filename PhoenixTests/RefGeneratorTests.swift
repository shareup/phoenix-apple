import XCTest
@testable import Phoenix

class RefGeneratorTests: XCTestCase {
    func testRefGenerator() {
        let generator = Phoenix.Ref.Generator()
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
}
