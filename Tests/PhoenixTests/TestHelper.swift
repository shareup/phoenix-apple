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
}

let testHelper = TestHelper()
