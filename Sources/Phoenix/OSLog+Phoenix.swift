import Foundation
import os.log

extension OSLog {
    private static var subsystem =
        Bundle.main.bundleIdentifier ?? "app.shareup.phoenix"

    static let phoenix = OSLog(subsystem: subsystem, category: "phoenix")
}
