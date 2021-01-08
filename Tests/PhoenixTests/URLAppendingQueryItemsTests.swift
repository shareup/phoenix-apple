import XCTest
@testable import Phoenix

class URLAppendingQueryItemsTests: XCTestCase {
    func testQueryItemsAreFormEncoded() throws {
        let url = try XCTUnwrap(URL(string: "ws://localhost:4003/socket"))
        let query = [
            "shared_secret": "tfa7DS9iIX/POq9/lAiIK4UZS+FXca1uQFMqfvJdpXY8zMUGF2vWEFXtotGcIMED"
        ]

        let urlWithQueryItems = url.appendingQueryItems(query)
        let expected = "ws://localhost:4003/socket?shared_secret=tfa7DS9iIX%2FPOq9%2FlAiIK4UZS%2BFXca1uQFMqfvJdpXY8zMUGF2vWEFXtotGcIMED"

        XCTAssertEqual(expected, urlWithQueryItems.absoluteString)
    }
}
