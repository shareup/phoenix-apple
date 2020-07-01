import Foundation

extension Collection {
    var isNotEmpty: Bool { return self.isEmpty == false }
}

extension Optional {
    var exists: Bool {
        switch self {
        case .none: return false
        case .some: return true
        }
    }
}
