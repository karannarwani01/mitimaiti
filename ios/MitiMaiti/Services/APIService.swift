import Foundation

actor APIService {
    static let shared = APIService()
    private var accessToken: String?
    private var refreshToken: String?
    private let http = HTTPClient.shared
    private let store = TokenStore.shared

    func bootstrap() async {
        let (a, r) = await store.load()
        self.accessToken = a
        self.refreshToken = r
    }

    func setTokens(access: String, refresh: String) async {
        self.accessToken = access
        self.refreshToken = refresh
        await store.save(access: access, refresh: refresh)
    }

    func clearTokens() async {
        self.accessToken = nil
        self.refreshToken = nil
        await store.clear()
    }

    func currentAccessToken() -> String? { accessToken }

    // MARK: - Auth

    func sendOTP(phone: String) async throws -> Bool {
        struct Body: Encodable { let phone: String }
        let _: EmptyData = try await http.request(.post, "/auth/login", body: Body(phone: phone))
        return true
    }

    func verifyOTP(phone: String, code: String) async throws -> (accessToken: String, refreshToken: String, isNew: Bool, profileCompleteness: Int) {
        struct Body: Encodable { let phone: String; let token: String }
        struct Resp: Decodable {
            struct UserStub: Decodable { let isNew: Bool; let profileCompleteness: Int? }
            struct Session: Decodable { let accessToken: String; let refreshToken: String }
            let user: UserStub
            let session: Session
        }
        do {
            let resp: Resp = try await http.request(.post, "/auth/verify", body: Body(phone: phone, token: code))
            await setTokens(access: resp.session.accessToken, refresh: resp.session.refreshToken)
            return (resp.session.accessToken, resp.session.refreshToken, resp.user.isNew, resp.user.profileCompleteness ?? 0)
        } catch APIError.unauthorized {
            throw APIError.invalidOTP
        }
    }

    func sendEmailOTP(email: String) async throws -> Bool {
        struct Body: Encodable { let email: String }
        let _: EmptyData = try await http.request(.post, "/auth/email/login", body: Body(email: email))
        return true
    }

    func verifyEmailOTP(email: String, code: String) async throws -> (accessToken: String, refreshToken: String, isNew: Bool, profileCompleteness: Int) {
        struct Body: Encodable { let email: String; let token: String }
        struct Resp: Decodable {
            struct UserStub: Decodable { let isNew: Bool; let profileCompleteness: Int? }
            struct Session: Decodable { let accessToken: String; let refreshToken: String }
            let user: UserStub
            let session: Session
        }
        do {
            let resp: Resp = try await http.request(.post, "/auth/email/verify", body: Body(email: email, token: code))
            await setTokens(access: resp.session.accessToken, refresh: resp.session.refreshToken)
            return (resp.session.accessToken, resp.session.refreshToken, resp.user.isNew, resp.user.profileCompleteness ?? 0)
        } catch APIError.unauthorized {
            throw APIError.invalidOTP
        }
    }

    func verifyGoogleIdToken(_ idToken: String) async throws -> (accessToken: String, refreshToken: String, isNew: Bool, profileCompleteness: Int, firstName: String?) {
        struct Resp: Decodable {
            struct UserStub: Decodable { let isNew: Bool; let profileCompleteness: Int?; let firstName: String? }
            struct Session: Decodable { let accessToken: String; let refreshToken: String }
            let user: UserStub
            let session: Session
        }
        // Pre-encode with default key strategy: backend zod expects camelCase
        // `idToken`; HTTPClient's encoder converts camelCase → snake_case which
        // would 400 the request.
        let raw = try JSONSerialization.data(withJSONObject: ["idToken": idToken])
        let resp: Resp = try await http.request(.post, "/auth/google/verify", rawBody: raw)
        await setTokens(access: resp.session.accessToken, refresh: resp.session.refreshToken)
        return (resp.session.accessToken, resp.session.refreshToken, resp.user.isNew, resp.user.profileCompleteness ?? 0, resp.user.firstName)
    }

    func verifyAppleIdToken(
        _ idToken: String,
        nonce: String?,
        givenName: String?,
        familyName: String?
    ) async throws -> (accessToken: String, refreshToken: String, isNew: Bool, profileCompleteness: Int, firstName: String?) {
        struct Resp: Decodable {
            struct UserStub: Decodable { let isNew: Bool; let profileCompleteness: Int?; let firstName: String? }
            struct Session: Decodable { let accessToken: String; let refreshToken: String }
            let user: UserStub
            let session: Session
        }
        // See verifyGoogleIdToken: backend wants camelCase, HTTPClient's
        // encoder snake-cases. Build the body manually and send rawBody.
        var bodyDict: [String: Any] = ["idToken": idToken]
        if let nonce { bodyDict["nonce"] = nonce }
        if givenName != nil || familyName != nil {
            var fullName: [String: Any] = [:]
            if let givenName { fullName["givenName"] = givenName }
            if let familyName { fullName["familyName"] = familyName }
            bodyDict["fullName"] = fullName
        }
        let raw = try JSONSerialization.data(withJSONObject: bodyDict)
        let resp: Resp = try await http.request(.post, "/auth/apple/verify", rawBody: raw)
        await setTokens(access: resp.session.accessToken, refresh: resp.session.refreshToken)
        return (resp.session.accessToken, resp.session.refreshToken, resp.user.isNew, resp.user.profileCompleteness ?? 0, resp.user.firstName)
    }

    func refresh() async throws {
        guard let refreshToken else { throw APIError.unauthorized }
        struct Body: Encodable { let refreshToken: String }
        struct Resp: Decodable { let accessToken: String; let refreshToken: String }
        let resp: Resp = try await http.request(.post, "/auth/refresh", body: Body(refreshToken: refreshToken))
        await setTokens(access: resp.accessToken, refresh: resp.refreshToken)
    }

    // MARK: - Photo upload

    func uploadPhoto(imageData: Data, mimeType: String = "image/jpeg") async throws -> UserPhoto {
        let boundary = UUID().uuidString
        var body = Data()
        let header = "--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"photo.jpg\"\r\nContent-Type: \(mimeType)\r\n\r\n"
        body.append(header.data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        let url = URL(string: AppConfig.baseURL + "/me/media")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token = accessToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.networkError }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 {
                try await refresh()
                return try await uploadPhoto(imageData: imageData, mimeType: mimeType)
            }
            let bodyString = String(data: data, encoding: .utf8) ?? "<binary>"
            throw APIError.serverError("HTTP \(http.statusCode): \(bodyString.prefix(200))")
        }

        struct Resp: Decodable {
            struct Media: Decodable {
                let id: String
                let urlThumb: String?
                let urlMedium: String?
                let urlOriginal: String
                let isPrimary: Bool?
                let sortOrder: Int?
            }
            let media: Media
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let envelope = try decoder.decode(APIEnvelope<Resp>.self, from: data)
        guard let resp = envelope.data else { throw APIError.serverError("Empty response") }
        return UserPhoto(
            id: resp.media.id,
            url: resp.media.urlOriginal,
            urlThumb: resp.media.urlThumb,
            urlMedium: resp.media.urlMedium,
            isPrimary: resp.media.isPrimary ?? false,
            sortOrder: resp.media.sortOrder ?? 0
        )
    }

    // MARK: - Profile

    func fetchProfile() async throws -> User {
        let resp: ProfileResponse = try await authedRequest(.get, "/me")
        return resp.toUser()
    }

    func updateProfile(_ updates: [String: Any]) async throws -> User {
        struct Resp: Decodable { let user: User }
        let body = try JSONSerialization.data(withJSONObject: updates)
        let resp: Resp = try await authedRequest(.patch, "/me", rawBody: body)
        return resp.user
    }

    // MARK: - Feed

    func fetchFeed(cursor: String? = nil) async throws -> [FeedCard] {
        struct Resp: Decodable { let cards: [FeedCard] }
        let path = cursor.map { "/feed?cursor=\($0)" } ?? "/feed"
        let resp: Resp = try await authedRequest(.get, path)
        return resp.cards
    }

    // MARK: - Actions

    func performAction(targetId: String, type: ActionType) async throws -> (isMatch: Bool, matchId: String?) {
        struct Body: Encodable { let targetId: String; let type: String }
        struct Resp: Decodable { let isMatch: Bool; let matchId: String? }
        let resp: Resp = try await authedRequest(.post, "/action", body: Body(targetId: targetId, type: String(describing: type)))
        return (resp.isMatch, resp.matchId)
    }

    func registerFcmToken(_ token: String, platform: String = "ios") async throws {
        struct Body: Encodable { let token: String; let platform: String }
        let _: EmptyData = try await authedRequest(.post, "/me/fcm-token", body: Body(token: token, platform: platform))
    }

    func answerPrompt(_ answer: String) async throws {
        struct Body: Encodable { let answer: String }
        let _: EmptyData = try await authedRequest(.post, "/action/prompt", body: Body(answer: answer))
    }

    func joinFamily(code: String, roleTag: String) async throws {
        struct Body: Encodable { let code: String; let roleTag: String }
        let _: EmptyData = try await authedRequest(.post, "/family/join", body: Body(code: code, roleTag: roleTag))
    }

    func rewind() async throws -> String {
        struct Resp: Decodable { let restoredId: String }
        let resp: Resp = try await authedRequest(.post, "/action/rewind")
        return resp.restoredId
    }

    // MARK: - Inbox

    func fetchInbox() async throws -> (likes: [LikedYouCard], matches: [Match]) {
        struct Resp: Decodable { let likes: [LikedYouCard]; let matches: [Match] }
        let resp: Resp = try await authedRequest(.get, "/inbox")
        return (resp.likes, resp.matches)
    }

    // MARK: - Chat

    func fetchMessages(matchId: String, before: String? = nil) async throws -> [Message] {
        struct Resp: Decodable { let messages: [Message] }
        var path = "/chat/\(matchId)"
        if let before { path += "?before=\(before)" }
        let resp: Resp = try await authedRequest(.get, path)
        return resp.messages
    }

    func sendChatMedia(matchId: String, imageData: Data, mimeType: String = "image/jpeg") async throws -> Message {
        let boundary = UUID().uuidString
        var body = Data()
        let header = "--\(boundary)\r\nContent-Disposition: form-data; name=\"media\"; filename=\"chat.jpg\"\r\nContent-Type: \(mimeType)\r\n\r\n"
        body.append(header.data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        let url = URL(string: AppConfig.baseURL + "/chat/\(matchId)/media")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token = accessToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.networkError }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 {
                try await refresh()
                return try await sendChatMedia(matchId: matchId, imageData: imageData, mimeType: mimeType)
            }
            throw APIError.serverError("Chat media upload failed: HTTP \(http.statusCode)")
        }

        struct Resp: Decodable { let message: Message }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(APIEnvelope<Resp>.self, from: data)
        guard let resp = envelope.data else { throw APIError.serverError("Empty response") }
        return resp.message
    }

    func sendMessage(matchId: String, content: String, type: MessageType = .text) async throws -> Message {
        struct Body: Encodable { let content: String; let type: String }
        struct Resp: Decodable { let message: Message }
        let resp: Resp = try await authedRequest(.post, "/chat/\(matchId)/messages", body: Body(content: content, type: String(describing: type)))
        return resp.message
    }

    // MARK: - Family

    func fetchFamily() async throws -> (members: [FamilyMember], suggestions: [FamilySuggestion]) {
        struct MembersResp: Decodable { let members: [FamilyMember] }
        struct SuggestionsResp: Decodable { let suggestions: [FamilySuggestion] }
        async let members: MembersResp = authedRequest(.get, "/family")
        async let suggestions: SuggestionsResp = authedRequest(.get, "/family/suggestions")
        let (m, s) = try await (members, suggestions)
        return (m.members, s.suggestions)
    }

    func generateInvite() async throws -> FamilyInvite {
        struct Resp: Decodable { let invite: FamilyInvite }
        let resp: Resp = try await authedRequest(.post, "/family/invite")
        return resp.invite
    }

    // MARK: - Safety

    func reportUser(userId: String, reason: String, details: String?) async throws {
        struct Body: Encodable { let targetUserId: String; let reason: String; let details: String? }
        let _: EmptyData = try await authedRequest(.post, "/safety/report", body: Body(targetUserId: userId, reason: reason, details: details))
    }

    func blockUser(userId: String) async throws {
        struct Body: Encodable { let targetUserId: String }
        let _: EmptyData = try await authedRequest(.post, "/safety/block", body: Body(targetUserId: userId))
    }

    // MARK: - Authed request helper with 401 → refresh → retry

    private func authedRequest<T: Decodable>(
        _ method: HTTPMethod,
        _ path: String,
        body: Encodable? = nil,
        rawBody: Data? = nil
    ) async throws -> T {
        do {
            return try await http.request(method, path, body: body, rawBody: rawBody, accessToken: accessToken)
        } catch APIError.unauthorized {
            try await refresh()
            return try await http.request(method, path, body: body, rawBody: rawBody, accessToken: accessToken)
        }
    }
}

// MARK: - API Errors

enum APIError: LocalizedError {
    case invalidOTP
    case networkError
    case unauthorized
    case rateLimited
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidOTP: return "Invalid verification code. Please try again."
        case .networkError: return "Network error. Please check your connection."
        case .unauthorized: return "Session expired. Please log in again."
        case .rateLimited: return "Too many requests. Please wait a moment."
        case .serverError(let msg): return msg
        }
    }
}
