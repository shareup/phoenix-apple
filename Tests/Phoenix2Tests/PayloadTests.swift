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

    func testSubscript() throws {
        let object: Payload = [
            "one": 1,
            "bool": true,
            "dict": [
                "key": "value"
            ]
        ]
        XCTAssertTrue(1 == object["one"])
        XCTAssertFalse("one" == object["one"])
        XCTAssertTrue(true == object["bool"])
        XCTAssertFalse(2.0 == object["bool"])
        XCTAssertTrue(Payload(["key": "value"]) == object["dict"])
        XCTAssertFalse(Payload.array([.string("one"), .boolean(false)]) == object["dict"])
        XCTAssertNil(object["doesNotExist"])

        let array: Payload = .array([.string("one"), .number(2), .boolean(false)])
        XCTAssertTrue("one" == array[0])
        XCTAssertTrue(2 == array[1])
        XCTAssertTrue(false == array[2])
        XCTAssertNil(array[3])

        let string: Payload = .string("text")
        XCTAssertNil(string["text"])
    }
}
