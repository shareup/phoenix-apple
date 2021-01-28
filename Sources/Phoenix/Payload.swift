import Foundation

public typealias Payload = [String: Any]

extension Dictionary where Key == String, Value == Any {
    var _debugDescription: String {
        let contents = self
            .map { (key, value) in
                let maxLength = 32
                let valueStr = String(describing: value)
                let truncatedValue = valueStr.count > maxLength ?
                    "\(valueStr.prefix(maxLength))..." :
                    valueStr
                return "\(key):\(truncatedValue)"
            }
            .joined(separator: ",")
        return "{\(contents)}"
    }
}
