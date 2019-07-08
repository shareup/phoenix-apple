import Foundation

struct PayloadValueWrapper {
    enum Errors: Error {
        case valueNotCodable
    }
    
    let value: Codable
}

extension Dictionary {
    func validPayload() throws -> [String: PayloadValueWrapper] {
        throw PayloadValueWrapper.Errors.valueNotCodable
    }
}

extension Dictionary where Key: StringProtocol, Value: Codable {
    func validPayload() throws -> [String: PayloadValueWrapper] {
        var dict = [String: PayloadValueWrapper]()
        
        for (key, value) in self {
            dict[String(key)] = PayloadValueWrapper(value: value)
        }
        
        return dict
    }
}
