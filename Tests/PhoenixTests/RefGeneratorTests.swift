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
    
    func testRefGeneratorCanStartAnywhere() {
        let generator = Ref.Generator(start: 11)
        
        XCTAssertEqual(generator.advance(), 12)
    }
    
    func testRefGeneratorRestartsForOverflow() {
        let generator = Ref.Generator(start: 9007199254740991)
        XCTAssertEqual(generator.advance(), 1)
    }
}
