import Foundation

enum RemoteDataError: LocalizedError {
    case invalidResponse(url: URL)
    case invalidTextEncoding(url: URL)
    case emptyPayload(source: String)

    var errorDescription: String? {
        switch self {
        case let .invalidResponse(url):
            return "Unable to load data from \(url.absoluteString)."
        case let .invalidTextEncoding(url):
            return "Unable to decode text response from \(url.absoluteString)."
        case let .emptyPayload(source):
            return "No data returned for \(source)."
        }
    }
}

struct RemoteDataClient: Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchData(from url: URL, headers: [String: String] = [:]) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("en-US,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        headers.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RemoteDataError.invalidResponse(url: url)
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw RemoteDataError.invalidResponse(url: url)
        }
        return data
    }

    func fetchString(from url: URL, headers: [String: String] = [:]) async throws -> String {
        let data = try await fetchData(from: url, headers: headers)
        if let value = String(data: data, encoding: .utf8) {
            return value
        }
        if let value = String(data: data, encoding: .isoLatin1) {
            return value
        }
        throw RemoteDataError.invalidTextEncoding(url: url)
    }

    func fetchJSON<T: Decodable>(
        _ type: T.Type,
        from url: URL,
        headers: [String: String] = [:],
        decoder: JSONDecoder = JSONDecoder()
    ) async throws -> T {
        let data = try await fetchData(from: url, headers: headers)
        return try decoder.decode(type, from: data)
    }
}
