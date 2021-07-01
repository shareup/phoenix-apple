import Foundation

extension Collection {
    var isNotEmpty: Bool { isEmpty == false }
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
    init(data: Data, encoding: String.Encoding) throws {
        guard let string = String(data: data, encoding: encoding) else {
            throw NSError(
                domain: "app.shareup.phoenix",
                code: 10000,
                userInfo: [
                    NSLocalizedDescriptionKey: "Could not decode '\(data)' into a UTF8 string",
                ]
            )
        }
        self = string
    }

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
                code: 10001,
                userInfo: [
                    NSLocalizedDescriptionKey: "Could not encode '\(self)' into UTF8 bytes",
                ]
            )
        }

        return data
    }
}

extension DispatchTimeoutResult: CustomStringConvertible {
    public var description: String {
        switch self {
        case .success: return "success"
        case .timedOut: return "timedOut"
        }
    }
}
