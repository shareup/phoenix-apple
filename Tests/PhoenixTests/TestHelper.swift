@testable import Phoenix
import XCTest

private let defaultLocalIP = "0.0.0.0"
private let defaultLocalDomain =
    "localhost.charlesproxy.com" // Allows viewing requests/responses in Charles

final class TestHelper {
    let gen = Ref.Generator()
    let userIDGen = Ref.Generator()

    var defaultURL: URL {
        URL(string: "ws://\(defaultLocalIP):4003/socket?user_id=\(userIDGen.advance().rawValue)")!
    }

    var defaultWebSocketURL: URL { Socket.webSocketURLV2(url: defaultURL) }

    func deserialize(_ data: Data) -> [Any?]? {
        try? JSONSerialization.jsonObject(with: data, options: []) as? [Any?]
    }

    func serialize(_ stuff: [Any?]) -> Data? {
        try? JSONSerialization.data(withJSONObject: stuff, options: [])
    }
}

let testHelper = TestHelper()
