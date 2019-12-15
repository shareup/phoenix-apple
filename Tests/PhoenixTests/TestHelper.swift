import XCTest
@testable import Phoenix

final class TestHelper {
    let gen = Ref.Generator()
    
    let defaultURL = URL(string: "ws://0.0.0.0:4000/socket?user_id=1")!
    let defaultWebSocketURL: URL
    
    init() {
        self.defaultWebSocketURL = try! Socket.webSocketURLV2(url: defaultURL)
    }
    
    func wait(for duration: Double = 0.5, test: () -> Bool) {
        let start = CFAbsoluteTimeGetCurrent()
        let max = start + duration
        
        while CFAbsoluteTimeGetCurrent() < max {
            if test() {
                return
            } else {
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
            }
        }
    }
    
    func bootExample() throws {
    }
    
    func quitExample() throws {
    }
    
    func deserialize(_ data: Data) -> [Any?]? {
        return try? JSONSerialization.jsonObject(with: data, options: []) as? [Any?]
    }

    func serialize(_ stuff: [Any?]) -> Data? {
        return try? JSONSerialization.data(withJSONObject: stuff, options: [])
    }
}
