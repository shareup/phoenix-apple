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

extension String {
    func data(
        using encoding: String.Encoding,
        allowLossyConversion: Bool = false
    ) throws -> Data {
        let optionalData: Data? = self.data(
            using: encoding,
            allowLossyConversion: allowLossyConversion
        )

        guard let data = optionalData else {
            throw NSError(
                domain: "app.shareup.phoenix",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Could not encode '\(self)' into UTF8 bytes"]
            )
        }

        return data
    }
}
