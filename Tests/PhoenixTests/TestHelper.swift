import XCTest
@testable import Phoenix

final class TestHelper {
    let gen = Ref.Generator()

    #if os(macOS)
        var proc: Process? = nil
    #endif
    
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
        #if os(macOS)
            let _proc = Process()
            proc = _proc

            _proc.launchPath = "/usr/local/bin/mix"
            _proc.arguments = ["phx.server"]

            let PATH = ProcessInfo.processInfo.environment["PATH"]!

            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "\(PATH):/usr/local/bin/"

            _proc.environment = env

            _proc.currentDirectoryURL = URL(fileURLWithPath: #file).appendingPathComponent("../example/")

            try _proc.run()

            sleep(1)
        #endif
    }
    
    func quitExample() throws {
        #if os(macOS)
            proc?.interrupt()
            sleep(1)
            proc?.interrupt()
            sleep(1)
            proc?.terminate()
            proc?.waitUntilExit()
        #endif
    }
    
    func deserialize(_ data: Data) -> [Any?]? {
        return try? JSONSerialization.jsonObject(with: data, options: []) as? [Any?]
    }

    func serialize(_ stuff: [Any?]) -> Data? {
        return try? JSONSerialization.data(withJSONObject: stuff, options: [])
    }
}
