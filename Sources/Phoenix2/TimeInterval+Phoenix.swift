import Foundation

extension TimeInterval {
    init(nanoseconds: UInt64) {
        self = Double(nanoseconds) / Double(NSEC_PER_SEC)
    }

    var nanoseconds: UInt64 {
        UInt64(min(self * Double(NSEC_PER_SEC), maxNanoseconds))
    }
}

private let maxNanoseconds = Double(UInt64.max - 1024)
