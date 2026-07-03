import Foundation

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case patch = "PATCH"
    case delete = "DELETE"
}

struct APIEnvelope<T: Decodable>: Decodable {
    let success: Bool
    let data: T?
    let error: String?
    let code: String?
    let message: String?
}

struct EmptyData: Decodable {}

actor HTTPClient {
    static let shared = HTTPClient()

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)

        self.decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        // Supabase timestamps carry fractional seconds ("…T12:15:47.069+00:00")
        // which the plain .iso8601 strategy cannot parse — every Date field
        // (chat history, inbox timestamps) would throw. Try fractional first.
        decoder.dateDecodingStrategy = .custom { d in
            let container = try d.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = HTTPClient.isoFractional.date(from: raw) { return date }
            if let date = HTTPClient.isoPlain.date(from: raw) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unparseable date: \(raw)"
            )
        }

        self.encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
    }

    static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    func request<T: Decodable>(
        _ method: HTTPMethod,
        _ path: String,
        body: Encodable? = nil,
        rawBody: Data? = nil,
        accessToken: String? = nil
    ) async throws -> T {
        let url = URL(string: AppConfig.baseURL + path)!
        var req = URLRequest(url: url)
        req.httpMethod = method.rawValue
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = accessToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let rawBody {
            req.httpBody = rawBody
        } else if let body {
            req.httpBody = try encoder.encode(AnyEncodable(body))
        }

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.networkError }

        switch http.statusCode {
        case 200..<300:
            do {
                let envelope = try decoder.decode(APIEnvelope<T>.self, from: data)
                if let payload = envelope.data { return payload }
                if T.self == EmptyData.self { return EmptyData() as! T }
                throw APIError.serverError("Empty response")
            } catch let decodeError as DecodingError {
                throw APIError.serverError("Decode failed: \(decodeError)")
            }
        case 401:
            throw APIError.unauthorized
        case 429:
            // The comment budget (5/day) is separate from the like budget —
            // surface it distinctly so the UI can offer a plain like instead.
            let envelope = try? decoder.decode(APIEnvelope<EmptyData>.self, from: data)
            if envelope?.code == "COMMENT_LIMIT_REACHED" { throw APIError.commentLimitReached }
            throw APIError.rateLimited
        default:
            let envelope = try? decoder.decode(APIEnvelope<EmptyData>.self, from: data)
            throw APIError.serverError(envelope?.error ?? envelope?.message ?? "HTTP \(http.statusCode)")
        }
    }
}

private struct AnyEncodable: Encodable {
    let wrapped: Encodable
    init(_ wrapped: Encodable) { self.wrapped = wrapped }
    func encode(to encoder: Encoder) throws { try wrapped.encode(to: encoder) }
}
