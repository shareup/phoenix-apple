import Foundation

// https://github.com/phoenixframework/phoenix/blob/e82161eb8f724a69cb17b8e2a22ea54e595b29ca/lib/phoenix/transports/websocket.ex#L17
//
// https://hexdocs.pm/plug/Plug.Conn.html#fetch_query_params/2
//
// Phoenix uses Plug.Conn.fetch_query_params() to collect the query parameters in
// Socket.connect().
// Plug.Conn.fetch_query_params() decodes the parameters as `x-www-form-urlencoded`. However,
// `URLComponents` does not encode query items according to the `x-www-form-urlencoded`
// standard.
// So, we have to manually encode all query parameters as `x-www-form-urlencoded`.

public extension URL {
    func appendingQueryItems(_ items: [String: String]) -> URL {
        guard var components = URLComponents(
            url: self,
            resolvingAgainstBaseURL: false
        ) else { fatalError() }

        var queryItems: [URLQueryItem] = components
            .queryItemsOrEmpty
            .map { item in
                URLQueryItem(
                    name: item.name,
                    value: item.value?.addingPercentEncodingForFormData()
                )
            }

        for (name, value) in items {
            queryItems.append(
                URLQueryItem(name: name, value: value.addingPercentEncodingForFormData())
            )
        }

        components.percentEncodedQueryItems = queryItems

        guard let url = components.url else { fatalError() }

        return url
    }
}

private extension URLComponents {
    var queryItemsOrEmpty: [URLQueryItem] {
        queryItems ?? []
    }
}

private extension String {
    func addingPercentEncodingForFormData() -> String? {
        let allowedCharacters = "*-._ "
        var allowedCharacterSet = CharacterSet.alphanumerics
        allowedCharacterSet.insert(charactersIn: allowedCharacters)

        return addingPercentEncoding(
            withAllowedCharacters: allowedCharacterSet
        )?.replacingOccurrences(of: " ", with: "+")
    }
}
