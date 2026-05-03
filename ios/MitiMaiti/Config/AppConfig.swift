import Foundation

enum AppConfig {
    static let baseURL: String = env("API_BASE_URL") ?? defaultBaseURL
    static let socketURL: String = env("WS_URL") ?? defaultSocketURL

    private static var defaultBaseURL: String {
        "https://mitimaiti-backend-tyxa.onrender.com/v1"
    }

    private static var defaultSocketURL: String {
        "https://mitimaiti-backend-tyxa.onrender.com"
    }

    private static func env(_ key: String) -> String? {
        guard let value = ProcessInfo.processInfo.environment[key], !value.isEmpty else { return nil }
        return value
    }
}
