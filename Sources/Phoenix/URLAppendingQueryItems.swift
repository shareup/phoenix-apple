import Foundation

extension URL {
    func appendingQueryItems(_ items: [String: String]) -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            fatalError()
        }
        
        var query = components.queryItems ?? []
        
        items.forEach { (name, value) in
            query.append(URLQueryItem(name: name, value: value))
        }
        
        components.queryItems = query
        
        guard let url = components.url else {
            fatalError()
        }
        
        return url
    }
}
