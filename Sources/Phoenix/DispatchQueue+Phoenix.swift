import Foundation

extension DispatchQueue {
    static var backgroundQueue: DispatchQueue {
        DispatchQueue(
            label: "app.shareup.phoenix.backgroundqueue",
            qos: .default,
            autoreleaseFrequency: .workItem,
            target: DispatchQueue.global()
        )
    }
}
