import Foundation
import os.log

extension OSLog {
    static let phoenix = OSLog(subsystem: subsystem, category: "phoenix")
}

private let subsystem =
    Bundle.main.bundleIdentifier ?? "app.shareup.phoenix"
