@testable import Phoenix2
import XCTest

final class PayloadTests: XCTestCase {
    func testCanEncodeToAndDecodeFromJSON() throws {
        let payload: Payload = [
            "one": 2,
            "two_text": "two",
            "pi": 3.14,
            "yes": true,
            "null": nil,
            "object": [
                "three": 3,
                "four_text": "four",
                "null": nil,
                "inner_array": [
                    "index_0",
                    false,
                    4.20,
                ] as [Any?],
            ] as [String: Any?],
        ]

        let jsonValue = payload.jsonValue
        let jsonDictionary = payload.jsonDictionary

        let encodedValue = try JSONSerialization.data(
            withJSONObject: jsonValue,
            options: [.sortedKeys]
        )

        let encodedDictionary = try JSONSerialization.data(
            withJSONObject: jsonDictionary,
            options: [.sortedKeys]
        )

        XCTAssertEqual(encodedValue, encodedDictionary)

        let decodedValue = try JSONSerialization.jsonObject(with: encodedValue)
        let decodedDictionary = try JSONSerialization.jsonObject(with: encodedDictionary)

        let valuePayload = Payload(decodedValue as! [String: Any?])
        let dictionaryPayload = Payload(decodedDictionary as! [String: Any?])

        XCTAssertEqual(valuePayload, dictionaryPayload)
        XCTAssertEqual(payload, dictionaryPayload)
    }
}
