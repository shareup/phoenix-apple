import Foundation

public typealias Payload = [String: Any]

extension Dictionary where Key == String, Value == Any {
    var _debugDescription: String {
        let contents = self
            .map { "\($0.key):\(String(describing: $0.value))" }
            .joined(separator: ",")
        return "{\(contents)}"
    }
}
