import Foundation

extension Collection {
    var isNotEmpty: Bool { return self.isEmpty == false }
}

extension Optional {
    var isNil: Bool {
        switch self {
        case .none: return true
        case .some: return false
        }
    }
}
