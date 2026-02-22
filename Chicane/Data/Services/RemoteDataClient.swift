import Foundation

enum RemoteDataError: LocalizedError {
    /// The server returned a 4xx status (client error — e.g. 404 Not Found, 410 Gone).
    case clientError(statusCode: Int, url: URL)
    /// The server returned a 5xx status (server error — e.g. 500, 503 Service Unavailable).
    case serverError(statusCode: Int, url: URL)
    /// A non-HTTP response or an unreadable response object.
    case invalidResponse(url: URL)
    /// Response body could not be decoded as text.
    case invalidTextEncoding(url: URL)
    /// Request succeeded but the payload was empty or produced no usable results.
    case emptyPayload(source: String)

    var errorDescription: String? {
        switch self {
        case let .clientError(code, url):
            return "Request failed (\(code)) for \(url.host ?? url.absoluteString). The resource may have moved or be unavailable."
        case let .serverError(code, url):
            return "Server error (\(code)) for \(url.host ?? url.absoluteString). Try again later."
        case let .invalidResponse(url):
            return "Unable to load data from \(url.absoluteString)."
        case let .invalidTextEncoding(url):
            return "Unable to decode text response from \(url.absoluteString)."
        case let .emptyPayload(source):
            return "No data returned for \(source)."
        }
    }

    /// `true` for transient failures worth retrying (server errors, not client errors).
    var isRetryable: Bool {
        switch self {
        case .serverError: return true
        case .clientError, .invalidResponse, .invalidTextEncoding, .emptyPayload: return false
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

        let code = httpResponse.statusCode
        switch code {
        case 200...299:
            return data
        case 400...499:
            throw RemoteDataError.clientError(statusCode: code, url: url)
        case 500...599:
            throw RemoteDataError.serverError(statusCode: code, url: url)
        default:
            throw RemoteDataError.invalidResponse(url: url)
        }
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
