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

    /// Restores a persisted session on app launch. Loads saved tokens; if
    /// present, validates them with GET /me. Returns nil when there is no
    /// stored session, the tokens are rejected (cleared), or /me can't be
    /// reached — in all those cases the caller should show the Welcome
    /// screen. Otherwise returns whether the user still needs onboarding
    /// (`true` → show onboarding, `false` → go straight to the main app).
    func restoreSession() async -> Bool? {
        await bootstrap()
        guard accessToken != nil else { return nil }
        do {
            let resp: ProfileResponse = try await authedRequest(.get, "/me")
            Message.currentUserId = resp.user.id
            return resp.user.needsOnboarding
                ?? ((resp.user.profileCompleteness ?? 0) < 50)
        } catch APIError.unauthorized {
            await clearTokens()
            return nil
        } catch {
            // Transient/network failure: keep tokens for a later retry but
            // fall back to the sign-in screen for this launch.
            return nil
        }
    }

    // MARK: - Auth

    func sendOTP(phone: String) async throws -> Bool {
        struct Body: Encodable { let phone: String }
        let _: EmptyData = try await http.request(.post, "/auth/login", body: Body(phone: phone))
        return true
    }

    func verifyOTP(phone: String, code: String) async throws -> (accessToken: String, refreshToken: String, isNew: Bool, profileCompleteness: Int, needsOnboarding: Bool) {
        struct Body: Encodable { let phone: String; let token: String }
        struct Resp: Decodable {
            struct UserStub: Decodable { let isNew: Bool; let profileCompleteness: Int?; let needsOnboarding: Bool? }
            struct Session: Decodable { let accessToken: String; let refreshToken: String }
            let user: UserStub
            let session: Session
        }
        do {
            let resp: Resp = try await http.request(.post, "/auth/verify", body: Body(phone: phone, token: code))
            await setTokens(access: resp.session.accessToken, refresh: resp.session.refreshToken)
            return (resp.session.accessToken, resp.session.refreshToken, resp.user.isNew, resp.user.profileCompleteness ?? 0, resp.user.needsOnboarding ?? resp.user.isNew)
        } catch APIError.unauthorized {
            throw APIError.invalidOTP
        }
    }

    func sendEmailOTP(email: String) async throws -> Bool {
        struct Body: Encodable { let email: String }
        let _: EmptyData = try await http.request(.post, "/auth/email/login", body: Body(email: email))
        return true
    }

    func verifyEmailOTP(email: String, code: String) async throws -> (accessToken: String, refreshToken: String, isNew: Bool, profileCompleteness: Int, needsOnboarding: Bool) {
        struct Body: Encodable { let email: String; let token: String }
        struct Resp: Decodable {
            struct UserStub: Decodable { let isNew: Bool; let profileCompleteness: Int?; let needsOnboarding: Bool? }
            struct Session: Decodable { let accessToken: String; let refreshToken: String }
            let user: UserStub
            let session: Session
        }
        do {
            let resp: Resp = try await http.request(.post, "/auth/email/verify", body: Body(email: email, token: code))
            await setTokens(access: resp.session.accessToken, refresh: resp.session.refreshToken)
            return (resp.session.accessToken, resp.session.refreshToken, resp.user.isNew, resp.user.profileCompleteness ?? 0, resp.user.needsOnboarding ?? resp.user.isNew)
        } catch APIError.unauthorized {
            throw APIError.invalidOTP
        }
    }

    func verifyGoogleIdToken(_ idToken: String) async throws -> (accessToken: String, refreshToken: String, isNew: Bool, profileCompleteness: Int, firstName: String?, needsOnboarding: Bool) {
        struct Resp: Decodable {
            struct UserStub: Decodable { let isNew: Bool; let profileCompleteness: Int?; let firstName: String?; let needsOnboarding: Bool? }
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
        return (resp.session.accessToken, resp.session.refreshToken, resp.user.isNew, resp.user.profileCompleteness ?? 0, resp.user.firstName, resp.user.needsOnboarding ?? resp.user.isNew)
    }

    func verifyAppleIdToken(
        _ idToken: String,
        nonce: String?,
        givenName: String?,
        familyName: String?
    ) async throws -> (accessToken: String, refreshToken: String, isNew: Bool, profileCompleteness: Int, firstName: String?, needsOnboarding: Bool) {
        struct Resp: Decodable {
            struct UserStub: Decodable { let isNew: Bool; let profileCompleteness: Int?; let firstName: String?; let needsOnboarding: Bool? }
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
        return (resp.session.accessToken, resp.session.refreshToken, resp.user.isNew, resp.user.profileCompleteness ?? 0, resp.user.firstName, resp.user.needsOnboarding ?? resp.user.isNew)
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
            if http.statusCode == 400 && bodyString.contains("MAX_PHOTOS") {
                throw APIError.photoLimitReached
            }
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

    // MARK: - Voice intro (Hinge-style)

    /// Upload a short voice introduction. Returns the public URL.
    func uploadVoiceIntro(audioData: Data) async throws -> String {
        let boundary = UUID().uuidString
        var body = Data()
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"audio\"; filename=\"voice_intro.m4a\"\r\nContent-Type: audio/mp4\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        let url = URL(string: AppConfig.baseURL + "/me/voice-intro")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token = accessToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.networkError }
        if http.statusCode == 401 {
            try await refresh()
            return try await uploadVoiceIntro(audioData: audioData)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.serverError("Voice intro upload failed: HTTP \(http.statusCode)")
        }

        struct Resp: Decodable { let voiceIntroUrl: String }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let envelope = try decoder.decode(APIEnvelope<Resp>.self, from: data)
        guard let resp = envelope.data else { throw APIError.serverError("Empty response") }
        return resp.voiceIntroUrl
    }

    func deleteVoiceIntro() async throws {
        let _: EmptyData = try await authedRequest(.delete, "/me/voice-intro")
    }

    // MARK: - Verification

    struct VerifyResult {
        let verified: Bool
        let similarity: Int?
        let message: String?
    }

    /// Selfie verification: the backend compares the selfie to the primary
    /// photo via AWS Rekognition. The selfie is never stored server-side.
    /// Max 3 attempts/day (429 after that).
    func verifySelfie(imageData: Data) async throws -> VerifyResult {
        let boundary = UUID().uuidString
        var body = Data()
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"selfie\"; filename=\"selfie.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        let url = URL(string: AppConfig.baseURL + "/me/verify")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token = accessToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.networkError }

        if http.statusCode == 401 {
            try await refresh()
            return try await verifySelfie(imageData: imageData)
        }
        if http.statusCode == 429 { throw APIError.rateLimited }

        struct Payload: Decodable {
            let isVerified: Bool?
            let similarity: Int?
        }
        struct ErrorBody: Decodable { let code: String?; let message: String? }
        struct Envelope: Decodable {
            let success: Bool
            let data: Payload?
            let error: ErrorBody?
            let message: String?
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let envelope = try decoder.decode(Envelope.self, from: data)

        guard (200..<300).contains(http.statusCode) else {
            let friendly: String
            switch envelope.error?.code {
            case "NO_PRIMARY_PHOTO": friendly = "Add a profile photo before verifying."
            case "ALREADY_VERIFIED": friendly = "Your profile is already verified!"
            case "FACE_NOT_DETECTED": friendly = "Couldn't detect a face. Use a clear, well-lit selfie."
            case "VERIFICATION_UNAVAILABLE": friendly = "Selfie verification is coming soon — hang tight!"
            default: friendly = envelope.error?.message ?? "Verification failed. Please try again."
            }
            throw APIError.serverError(friendly)
        }

        // A failed match also returns 200, with success:false + similarity
        if envelope.success, envelope.data?.isVerified == true {
            return VerifyResult(verified: true, similarity: envelope.data?.similarity, message: nil)
        }
        return VerifyResult(
            verified: false,
            similarity: envelope.data?.similarity,
            message: envelope.error?.message
                ?? "The selfie didn't match your photo closely enough. Try better lighting and a clearer angle."
        )
    }

    // MARK: - Profile

    func fetchProfile() async throws -> User {
        let resp: ProfileResponse = try await authedRequest(.get, "/me")
        // Message ownership checks need to know who "me" is.
        Message.currentUserId = resp.user.id
        return resp.toUser()
    }

    /// PATCH /me, then re-fetch the fresh profile. The PATCH response is
    /// { updated, profileCompleteness } — decoding it as { user } made every
    /// successful save on iOS look like a failure.
    func updateProfile(_ updates: [String: Any]) async throws -> User {
        struct Resp: Decodable { let profileCompleteness: Int }
        let body = try JSONSerialization.data(withJSONObject: updates)
        let _: Resp = try await authedRequest(.patch, "/me", rawBody: body)
        return try await fetchProfile()
    }

    /// Raw user_settings row (+ snooze flag) from GET /me, so the Settings
    /// screen can seed its state from the server instead of hardcoded defaults.
    struct ServerSettings: Decodable {
        let discoveryEnabled: Bool?
        let incognitoMode: Bool?
        let showFullName: Bool?
        let ageMin: Int?
        let ageMax: Int?
        let heightMin: Int?
        let heightMax: Int?
        let genderPreference: String?
        let verifiedOnly: Bool?
        let intentFilter: String?
        let religionFilter: String?
        let educationFilter: String?
        let smokingFilter: String?
        let drinkingFilter: String?
        let fluencyFilter: String?
        let gotraFilter: String?
        let dietaryFilter: String?
        let isSnoozed: Bool?
    }

    func fetchSettings() async throws -> ServerSettings {
        struct UserStatus: Decodable { let isSnoozed: Bool? }
        struct Resp: Decodable { let settings: ServerSettings?; let user: UserStatus? }
        let resp: Resp = try await authedRequest(.get, "/me")
        let s = resp.settings
        return ServerSettings(
            discoveryEnabled: s?.discoveryEnabled,
            incognitoMode: s?.incognitoMode,
            showFullName: s?.showFullName,
            ageMin: s?.ageMin,
            ageMax: s?.ageMax,
            heightMin: s?.heightMin,
            heightMax: s?.heightMax,
            genderPreference: s?.genderPreference,
            verifiedOnly: s?.verifiedOnly,
            intentFilter: s?.intentFilter,
            religionFilter: s?.religionFilter,
            educationFilter: s?.educationFilter,
            smokingFilter: s?.smokingFilter,
            drinkingFilter: s?.drinkingFilter,
            fluencyFilter: s?.fluencyFilter,
            gotraFilter: s?.gotraFilter,
            dietaryFilter: s?.dietaryFilter,
            isSnoozed: resp.user?.isSnoozed
        )
    }

    /// PATCH /me with raw section payload (basics/user/settings/…). Returns
    /// the backend-recalculated profile completeness. Matches the actual
    /// PATCH /me response shape ({ updated, profileCompleteness }).
    func patchMe(_ updates: [String: Any]) async throws -> Int {
        struct Resp: Decodable { let profileCompleteness: Int }
        let body = try JSONSerialization.data(withJSONObject: updates)
        let resp: Resp = try await authedRequest(.patch, "/me", rawBody: body)
        return resp.profileCompleteness
    }

    // MARK: - Feed

    /// Server-authoritative daily like/rewind counters delivered with the feed.
    struct DailyLimits: Decodable {
        let likesUsedToday: Int?
        let likesRemaining: Int?
        let rewindsUsedToday: Int?
        let rewindsRemaining: Int?
    }

    func fetchFeed(cursor: String? = nil) async throws -> (cards: [FeedCard], limits: DailyLimits?) {
        struct Resp: Decodable { let cards: [FeedCard]; let limits: DailyLimits? }
        let path = cursor.map { "/feed?cursor=\($0)" } ?? "/feed"
        let resp: Resp = try await authedRequest(.get, path)
        return (resp.cards, resp.limits)
    }

    /// "Most Compatible" daily pick — one card, stable for the day, or nil
    /// when there's no candidate left.
    func fetchDailyPick() async throws -> FeedCard? {
        struct Resp: Decodable { let card: FeedCard? }
        let resp: Resp = try await authedRequest(.get, "/feed/daily-pick")
        return resp.card
    }

    // MARK: - Actions

    func performAction(targetId: String, type: ActionType) async throws -> (isMatch: Bool, matchId: String?, likesUsedToday: Int?) {
        // Field name snake-cases to target_user_id (what the backend expects).
        struct Body: Encodable { let targetUserId: String; let type: String }
        struct Resp: Decodable { let isMatch: Bool; let matchId: String?; let likesUsedToday: Int? }
        let resp: Resp = try await authedRequest(.post, "/action", body: Body(targetUserId: targetId, type: type.rawValue))
        return (resp.isMatch, resp.matchId, resp.likesUsedToday)
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
        // Backend returns { rewound_target_id, rewinds_remaining, rewinds_used_today }
        struct Resp: Decodable { let rewoundTargetId: String }
        let resp: Resp = try await authedRequest(.post, "/action/rewind")
        return resp.rewoundTargetId
    }

    // MARK: - Inbox

    func fetchInbox() async throws -> (likes: [LikedYouCard], matches: [Match]) {
        // Backend shape: { liked_you: { count, profiles: [flat card] },
        //                  matches:   { count, profiles: [flat item] } }
        struct FlatPhoto: Decodable {
            let url: String?
            let urlThumb: String?
            let urlMedium: String?
            let isPrimary: Bool?
            let sortOrder: Int?
        }
        struct FlatLike: Decodable {
            let id: String
            let displayName: String?
            let firstName: String?
            let age: Int?
            let city: String?
            let isVerified: Bool?
            let photos: [FlatPhoto]?
            let aboutMe: String?
            let interests: [String]?
            let culturalScore: Int?
            let culturalBadge: CulturalBadge?
            let likeLabel: String?
            let likedAt: Date?
        }
        struct LastMsg: Decodable {
            let content: String?
            let sentAt: Date?
            let isYou: Bool?
            let msgType: MessageType?
        }
        struct FlatMatch: Decodable {
            let matchId: String
            let userId: String
            let displayName: String?
            let firstName: String?
            let age: Int?
            let city: String?
            let isVerified: Bool?
            let photo: FlatPhoto?
            let culturalScore: Int?
            let status: MatchStatus?
            let matchedAt: Date?
            let expiresAt: Date?
            let firstMsgBy: String?
            let firstMsgByMe: Bool?
            let firstMsgLocked: Bool?
            let firstMsgAt: Date?
            let lastMessage: LastMsg?
            let unreadCount: Int?
        }
        struct Group<T: Decodable>: Decodable { let count: Int; let profiles: [T] }
        struct Resp: Decodable { let likedYou: Group<FlatLike>; let matches: Group<FlatMatch> }

        let resp: Resp = try await authedRequest(.get, "/inbox")

        let likes = resp.likedYou.profiles.map { like in
            LikedYouCard(
                id: like.id,
                user: User(
                    id: like.id,
                    displayName: like.displayName ?? like.firstName ?? "",
                    bio: like.aboutMe,
                    city: like.city,
                    isVerified: like.isVerified ?? false,
                    photos: (like.photos ?? []).compactMap { p in
                        guard let url = p.url ?? p.urlMedium else { return nil }
                        return UserPhoto(url: url, urlThumb: p.urlThumb, urlMedium: p.urlMedium,
                                         isPrimary: p.isPrimary ?? false, sortOrder: p.sortOrder ?? 0)
                    },
                    interests: like.interests ?? [],
                    ageYears: like.age
                ),
                likedAt: like.likedAt ?? Date(),
                likeLabel: like.likeLabel ?? "Liked your profile",
                culturalScore: like.culturalScore ?? 0,
                culturalBadge: like.culturalBadge ?? .none
            )
        }

        let matches = resp.matches.profiles.map { m in
            Match(
                id: m.matchId,
                otherUser: User(
                    id: m.userId,
                    displayName: m.displayName ?? m.firstName ?? "",
                    city: m.city,
                    isVerified: m.isVerified ?? false,
                    photos: m.photo.flatMap { p -> [UserPhoto]? in
                        guard let url = p.url ?? p.urlMedium else { return nil }
                        return [UserPhoto(url: url, urlThumb: p.urlThumb, urlMedium: p.urlMedium, isPrimary: true)]
                    } ?? [],
                    ageYears: m.age
                ),
                status: m.status ?? .pendingFirstMessage,
                matchedAt: m.matchedAt ?? Date(),
                expiresAt: m.expiresAt,
                lastMessage: m.lastMessage.flatMap { lm in
                    guard let content = lm.content else { return nil }
                    return Message(
                        matchId: m.matchId,
                        senderId: (lm.isYou ?? false) ? (Message.currentUserId ?? "current-user-id") : m.userId,
                        content: content,
                        msgType: lm.msgType ?? .text,
                        createdAt: lm.sentAt ?? Date(),
                        isYouFlag: lm.isYou
                    )
                },
                unreadCount: m.unreadCount ?? 0,
                firstMsgBy: m.firstMsgBy,
                firstMsgByMe: m.firstMsgByMe,
                firstMsgLocked: m.firstMsgLocked ?? false,
                firstMsgAt: m.firstMsgAt
            )
        }

        return (likes, matches)
    }

    // MARK: - Chat

    func fetchMessages(matchId: String, before: String? = nil) async throws -> (messages: [Message], icebreakers: [String]) {
        struct FlatIcebreaker: Decodable { let question: String? }
        struct Resp: Decodable { let messages: [Message]; let icebreakers: [FlatIcebreaker]? }
        var path = "/chat/\(matchId)"
        if let before { path += "?before=\(before)" }
        let resp: Resp = try await authedRequest(.get, path)
        return (resp.messages, (resp.icebreakers ?? []).compactMap { $0.question })
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

        // Media uploads return a FLAT payload — no `message` wrapper:
        // { messageId, msgType, mediaUrl, mediaType, createdAt }
        struct Resp: Decodable {
            let messageId: String
            let msgType: MessageType?
            let mediaUrl: String?
            let createdAt: Date?
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { d in
            let container = try d.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = HTTPClient.isoFractional.date(from: raw) { return date }
            if let date = HTTPClient.isoPlain.date(from: raw) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unparseable date: \(raw)")
        }
        let envelope = try decoder.decode(APIEnvelope<Resp>.self, from: data)
        guard let resp = envelope.data else { throw APIError.serverError("Empty response") }
        return Message(
            id: resp.messageId,
            matchId: matchId,
            senderId: Message.currentUserId ?? "current-user-id",
            content: "",
            mediaUrl: resp.mediaUrl,
            msgType: resp.msgType ?? .photo,
            status: .sent,
            createdAt: resp.createdAt ?? Date()
        )
    }

    /// Upload a chat voice clip (m4a/AAC) with its duration in seconds.
    func sendChatVoice(matchId: String, audioData: Data, durationSeconds: Int, mimeType: String = "audio/mp4") async throws -> Message {
        let boundary = UUID().uuidString
        var body = Data()
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"audio\"; filename=\"voice.m4a\"\r\nContent-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"duration\"\r\n\r\n\(durationSeconds)\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        let url = URL(string: AppConfig.baseURL + "/chat/\(matchId)/audio")!
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
                return try await sendChatVoice(matchId: matchId, audioData: audioData, durationSeconds: durationSeconds, mimeType: mimeType)
            }
            throw APIError.serverError("Chat voice upload failed: HTTP \(http.statusCode)")
        }

        // Voice uploads return a FLAT payload — no `message` wrapper:
        // { messageId, msgType, mediaUrl, mediaType, durationSeconds, createdAt }
        struct Resp: Decodable {
            let messageId: String
            let mediaUrl: String?
            let durationSeconds: Int?
            let createdAt: Date?
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { d in
            let container = try d.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = HTTPClient.isoFractional.date(from: raw) { return date }
            if let date = HTTPClient.isoPlain.date(from: raw) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unparseable date: \(raw)")
        }
        let envelope = try decoder.decode(APIEnvelope<Resp>.self, from: data)
        guard let resp = envelope.data else { throw APIError.serverError("Empty response") }
        return Message(
            id: resp.messageId,
            matchId: matchId,
            senderId: Message.currentUserId ?? "current-user-id",
            content: "",
            mediaUrl: resp.mediaUrl,
            msgType: .voice,
            status: .sent,
            createdAt: resp.createdAt ?? Date(),
            durationSeconds: resp.durationSeconds ?? durationSeconds
        )
    }

    func sendMessage(matchId: String, content: String, type: MessageType = .text) async throws -> Message {
        struct Body: Encodable { let content: String; let type: String }
        struct Resp: Decodable { let message: Message }
        let resp: Resp = try await authedRequest(.post, "/chat/\(matchId)/messages", body: Body(content: content, type: type.rawValue))
        return resp.message
    }

    /// Edit a text message. The backend owns the " [edited]" marker, so send raw text.
    func editMessage(matchId: String, messageId: String, content: String) async throws {
        struct Body: Encodable { let content: String }
        let _: EmptyData = try await authedRequest(.patch, "/chat/\(matchId)/messages/\(messageId)", body: Body(content: content))
    }

    /// Delete a message (sender-only, hard delete on the server).
    func deleteMessage(matchId: String, messageId: String) async throws {
        let _: EmptyData = try await authedRequest(.delete, "/chat/\(matchId)/messages/\(messageId)")
    }

    /// Dissolve a match (either participant can unmatch; irreversible).
    func unmatch(matchId: String) async throws {
        let _: EmptyData = try await authedRequest(.post, "/chat/\(matchId)/unmatch")
    }

    /// Add/replace the current user's reaction on a message.
    func setReaction(matchId: String, messageId: String, emoji: String) async throws {
        struct Body: Encodable { let emoji: String }
        let _: EmptyData = try await authedRequest(.post, "/chat/\(matchId)/messages/\(messageId)/reaction", body: Body(emoji: emoji))
    }

    /// Remove the current user's reaction from a message.
    func clearReaction(matchId: String, messageId: String) async throws {
        let _: EmptyData = try await authedRequest(.delete, "/chat/\(matchId)/messages/\(messageId)/reaction")
    }

    // MARK: - Family

    func fetchFamily() async throws -> (members: [FamilyMember], suggestions: [FamilySuggestion]) {
        // GET /family member items: { id, name, relationship, status,
        // permissions {camelCase}, joinedAt } — no phone.
        struct FlatMember: Decodable {
            let id: String
            let name: String?
            let relationship: String?
            let status: String? // may carry values outside the client enum (e.g. "expired")
            let permissions: FamilyPermissions?
            let joinedAt: Date?
        }
        struct MembersResp: Decodable { let members: [FlatMember] }

        // GET /family/suggestions items: { id, suggestedUserId,
        // suggestedBy { userId, displayName },
        // suggestedProfile { displayName, city, country, age, photo },
        // note, status, createdAt }
        struct FlatSuggester: Decodable { let userId: String?; let displayName: String? }
        struct FlatSuggestedProfile: Decodable {
            let displayName: String?
            let city: String?
            let country: String?
            let age: Int?
            let photo: String?
        }
        struct FlatSuggestion: Decodable {
            let id: String
            let suggestedUserId: String?
            let suggestedBy: FlatSuggester?
            let suggestedProfile: FlatSuggestedProfile?
            let note: String?
            let createdAt: Date?
        }
        struct SuggestionsResp: Decodable { let suggestions: [FlatSuggestion] }

        async let membersReq: MembersResp = authedRequest(.get, "/family")
        async let suggestionsReq: SuggestionsResp = authedRequest(.get, "/family/suggestions")
        let (m, s) = try await (membersReq, suggestionsReq)

        let members = m.members.map { fm in
            FamilyMember(
                id: fm.id,
                name: fm.name ?? "Family Member",
                phone: "",
                relationship: fm.relationship ?? "",
                status: FamilyMemberStatus(rawValue: fm.status ?? "") ?? .active,
                permissions: fm.permissions ?? .allEnabled,
                joinedAt: fm.joinedAt ?? Date()
            )
        }

        let suggestions = s.suggestions.map { fs in
            FamilySuggestion(
                id: fs.id,
                suggestedBy: FamilyMember(
                    id: fs.suggestedBy?.userId ?? "",
                    name: fs.suggestedBy?.displayName ?? "Family Member",
                    phone: "",
                    relationship: ""
                ),
                suggestedUser: User(
                    id: fs.suggestedUserId ?? "",
                    displayName: fs.suggestedProfile?.displayName ?? "",
                    city: fs.suggestedProfile?.city,
                    country: fs.suggestedProfile?.country,
                    photos: fs.suggestedProfile?.photo.map {
                        [UserPhoto(url: $0, urlThumb: $0, isPrimary: true)]
                    } ?? [],
                    ageYears: fs.suggestedProfile?.age
                ),
                note: fs.note,
                suggestedAt: fs.createdAt ?? Date()
            )
        }

        return (members, suggestions)
    }

    func generateInvite() async throws -> FamilyInvite {
        // Response fields sit at the top of `data` — no `invite` wrapper:
        // { inviteId, code, deepLink, expiresAt, currentMembers, maxMembers }
        struct Resp: Decodable {
            let code: String
            let deepLink: String?
            let expiresAt: Date?
            let currentMembers: Int?
            let maxMembers: Int?
        }
        let resp: Resp = try await authedRequest(.post, "/family/invite")
        return FamilyInvite(
            code: resp.code,
            deepLink: resp.deepLink ?? "",
            expiresAt: resp.expiresAt ?? Calendar.current.date(byAdding: .hour, value: 48, to: Date())!,
            currentMembers: resp.currentMembers ?? 0,
            maxMembers: resp.maxMembers ?? 3
        )
    }

    /// Update a family member (permissions / is_revoked / revoke_all). Raw JSON
    /// body so keys pass through verbatim (permission keys are camelCase).
    func updateFamilyMember(memberId: String, body: [String: Any]) async throws {
        let data = try JSONSerialization.data(withJSONObject: body)
        let _: EmptyData = try await authedRequest(.patch, "/family/\(memberId)", rawBody: data)
    }

    // MARK: - Safety

    func reportUser(userId: String, reason: String, details: String?) async throws {
        // Field name snake-cases to reported_id (what the backend expects).
        struct Body: Encodable { let reportedId: String; let reason: String; let details: String? }
        let _: EmptyData = try await authedRequest(.post, "/safety/report", body: Body(reportedId: userId, reason: reason, details: details))
    }

    func blockUser(userId: String) async throws {
        // Field name snake-cases to blocked_id (what the backend expects).
        struct Body: Encodable { let blockedId: String }
        let _: EmptyData = try await authedRequest(.post, "/safety/block", body: Body(blockedId: userId))
    }

    /// GDPR data export: returns pretty-printed JSON of everything the
    /// backend stores about the user (rate-limited to 2/hour server-side).
    func exportData() async throws -> Data {
        let url = URL(string: AppConfig.baseURL + "/me/export")!
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        if let token = accessToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.networkError }
        if http.statusCode == 401 {
            try await refresh()
            return try await exportData()
        }
        if http.statusCode == 429 { throw APIError.rateLimited }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.serverError("Export failed: HTTP \(http.statusCode)")
        }
        // Unwrap the { success, data } envelope and pretty-print
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let payload = obj["data"],
           let pretty = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
            return pretty
        }
        return data
    }

    /// Permanently delete the account server-side (soft-delete, 30-day window).
    func deleteAccount() async throws {
        struct Body: Encodable { let action: String }
        let _: EmptyData = try await authedRequest(.post, "/auth/delete", body: Body(action: "delete"))
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
    case photoLimitReached
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidOTP: return "Invalid verification code. Please try again."
        case .networkError: return "Network error. Please check your connection."
        case .unauthorized: return "Session expired. Please log in again."
        case .rateLimited: return "Too many requests. Please wait a moment."
        case .photoLimitReached: return "You've reached the maximum of 6 photos."
        case .serverError(let msg): return msg
        }
    }
}
