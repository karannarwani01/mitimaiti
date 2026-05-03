package com.mitimaiti.app.services

import com.mitimaiti.app.models.*
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.MultipartBody
import okhttp3.RequestBody.Companion.toRequestBody
import java.time.LocalDate

/**
 * Live backend service. All calls hit production backend (no mocks).
 * Endpoints (backend/src/routes/):
 *   POST /v1/auth/login        → sendOTP
 *   POST /v1/auth/verify       → verifyOTP
 *   POST /v1/auth/refresh      → refreshToken
 *   POST /v1/auth/delete       → logout / deleteAccount
 *   GET  /v1/me                → fetchProfile
 *   PATCH /v1/me               → updateProfile
 *   GET  /v1/feed              → fetchFeed
 *   POST /v1/action            → performAction
 *   POST /v1/action/rewind     → rewind
 *   GET  /v1/inbox             → fetchInbox
 *   GET  /v1/chat/:matchId     → fetchMessages
 *   POST /v1/chat/:matchId/messages → sendMessage (REST fallback)
 *   POST /v1/family/invite     → generateInvite
 *   GET  /v1/family            → fetchFamily
 *   POST /v1/safety/report     → reportUser
 *   POST /v1/safety/block      → blockUser
 *
 * Real-time chat uses SocketManager (Socket.IO).
 */
object APIService {
    private var tokenManager: TokenManager? = null
    private val api: MitiMaitiApi by lazy { HttpClient.retrofit.create(MitiMaitiApi::class.java) }

    private var accessToken: String? = null
    private var refreshToken: String? = null

    fun init(tokenManager: TokenManager) {
        this.tokenManager = tokenManager
        HttpClient.init(tokenManager)
    }

    fun setTokens(access: String, refresh: String) { accessToken = access; refreshToken = refresh }
    fun clearTokens() { accessToken = null; refreshToken = null }

    // ──────────────────── AUTH ────────────────────

    suspend fun sendOTP(phone: String): Result<Boolean> {
        return try {
            val response = api.sendOTP(mapOf("phone" to phone))
            if (response.isSuccessful) Result.success(true)
            else Result.failure(APIError.NetworkError)
        } catch (e: Exception) { Result.failure(APIError.NetworkError) }
    }

    suspend fun verifyOTP(phone: String, code: String): Result<Pair<User, Boolean>> {
        return try {
            val response = api.verifyOTP(mapOf("phone" to phone, "token" to code))
            if (response.isSuccessful) {
                val body = response.body() ?: return Result.failure(APIError.ServerError)
                val session = body["session"] as? Map<*, *>
                val userMap = body["user"] as? Map<*, *>
                val token = session?.get("access_token") as? String ?: ""
                val refresh = session?.get("refresh_token") as? String ?: ""
                val userId = userMap?.get("id") as? String ?: ""
                val isNew = userMap?.get("is_new") as? Boolean ?: false
                setTokens(token, refresh)
                tokenManager?.saveTokens(token, refresh, userId)
                SocketManager.shared.connect(token)
                Result.success(Pair(parseUser(userMap), isNew))
            } else {
                if (response.code() == 401) Result.failure(APIError.InvalidOTP)
                else Result.failure(APIError.ServerError)
            }
        } catch (e: Exception) { Result.failure(APIError.NetworkError) }
    }

    // ──────────────────── PROFILE ────────────────────

    suspend fun fetchProfile(): Result<User> {
        return try {
            val response = api.getProfile()
            if (response.isSuccessful) Result.success(parseUser(response.body()))
            else Result.failure(APIError.ServerError)
        } catch (e: Exception) { Result.failure(APIError.NetworkError) }
    }

    suspend fun updateProfile(updates: Map<String, Any>): Result<User> {
        return try {
            val response = api.updateProfile(updates)
            if (response.isSuccessful) Result.success(parseUser(response.body()))
            else Result.failure(APIError.ServerError)
        } catch (e: Exception) {
            android.util.Log.e("APIService", "updateProfile failed", e)
            Result.failure(APIError.NetworkError)
        }
    }

    suspend fun uploadPhoto(bytes: ByteArray, mimeType: String = "image/jpeg"): Result<UserPhoto> {
        return try {
            val body = bytes.toRequestBody(mimeType.toMediaTypeOrNull())
            val part = MultipartBody.Part.createFormData("file", "photo.jpg", body)
            val response = api.uploadPhoto(part)
            if (response.isSuccessful) {
                val media = (response.body()?.get("media") as? Map<*, *>) ?: return Result.failure(APIError.ServerError)
                Result.success(UserPhoto(
                    id = media["id"] as? String ?: java.util.UUID.randomUUID().toString(),
                    url = media["url_original"] as? String ?: "",
                    urlThumb = media["url_thumb"] as? String,
                    urlMedium = media["url_medium"] as? String,
                    isPrimary = media["is_primary"] as? Boolean ?: false,
                    sortOrder = (media["sort_order"] as? Number)?.toInt() ?: 0
                ))
            } else Result.failure(APIError.ServerError)
        } catch (e: Exception) { Result.failure(APIError.NetworkError) }
    }

    suspend fun deletePhoto(id: String): Result<Boolean> {
        return try {
            val response = api.deletePhoto(id)
            if (response.isSuccessful) Result.success(true) else Result.failure(APIError.ServerError)
        } catch (e: Exception) { Result.failure(APIError.NetworkError) }
    }

    suspend fun answerPrompt(answer: String): Result<Boolean> {
        return try {
            val response = api.answerPrompt(mapOf("answer" to answer))
            if (response.isSuccessful) Result.success(true) else Result.failure(APIError.ServerError)
        } catch (e: Exception) { Result.failure(APIError.NetworkError) }
    }

    suspend fun joinFamily(code: String, roleTag: String): Result<Boolean> {
        return try {
            val response = api.joinFamily(mapOf("code" to code, "roleTag" to roleTag))
            if (response.isSuccessful) Result.success(true) else Result.failure(APIError.ServerError)
        } catch (e: Exception) { Result.failure(APIError.NetworkError) }
    }

    suspend fun registerFcmToken(token: String, platform: String = "android"): Result<Boolean> {
        return try {
            val response = api.registerFcmToken(mapOf("token" to token, "platform" to platform))
            if (response.isSuccessful) Result.success(true) else Result.failure(APIError.ServerError)
        } catch (e: Exception) { Result.failure(APIError.NetworkError) }
    }

    // ──────────────────── FEED ────────────────────

    suspend fun fetchFeed(cursor: String? = null): Result<List<FeedCard>> {
        return try {
            val response = api.getFeed(cursor)
            if (response.isSuccessful) {
                val body = response.body() ?: return Result.success(emptyList())
                Result.success(parseFeedCards(body["cards"] as? List<*>))
            } else Result.failure(APIError.ServerError)
        } catch (e: Exception) { Result.failure(APIError.NetworkError) }
    }

    // ──────────────────── ACTIONS ────────────────────

    suspend fun performAction(targetId: String, type: String): Result<Match?> {
        return try {
            val response = api.performAction(mapOf("targetUserId" to targetId, "type" to type))
            if (response.isSuccessful) {
                val body = response.body()
                val matchData = body?.get("match") as? Map<*, *>
                if (matchData != null) Result.success(parseMatch(matchData))
                else Result.success(null)
            } else Result.failure(APIError.ServerError)
        } catch (e: Exception) { Result.failure(APIError.NetworkError) }
    }

    suspend fun rewind(): Result<Boolean> {
        return try {
            val response = api.rewind()
            Result.success(response.isSuccessful)
        } catch (e: Exception) { Result.failure(APIError.NetworkError) }
    }

    // ──────────────────── INBOX ────────────────────

    suspend fun fetchInbox(): Result<Pair<List<LikedYouCard>, List<Match>>> {
        return try {
            val response = api.getInbox()
            if (response.isSuccessful) {
                val body = response.body() ?: return Result.success(Pair(emptyList(), emptyList()))
                val likes = parseLikes(body["liked_you"] as? List<*>)
                val matches = parseMatches(body["matches"] as? List<*>)
                Result.success(Pair(likes, matches))
            } else Result.failure(APIError.ServerError)
        } catch (e: Exception) { Result.failure(APIError.NetworkError) }
    }

    // ──────────────────── CHAT ────────────────────

    suspend fun fetchMessages(matchId: String): Result<List<Message>> {
        return try {
            val response = api.getMessages(matchId)
            if (response.isSuccessful) {
                val body = response.body() ?: return Result.success(emptyList())
                Result.success(parseMessages(body["messages"] as? List<*>))
            } else Result.failure(APIError.ServerError)
        } catch (e: Exception) { Result.failure(APIError.NetworkError) }
    }

    suspend fun sendMessage(matchId: String, content: String, type: MessageType = MessageType.TEXT): Result<Message> {
        if (SocketManager.shared.isConnected.value) {
            SocketManager.shared.sendMessage(matchId, content, type.value)
            return Result.success(Message(matchId = matchId, senderId = tokenManager?.getUserId().toString(), content = content, msgType = type, status = MessageStatus.SENDING))
        }
        return try {
            val response = api.sendMessage(matchId, mapOf("content" to content, "msgType" to type.value))
            if (response.isSuccessful) Result.success(parseMessage(response.body()?.get("message") as? Map<*, *>))
            else Result.failure(APIError.ServerError)
        } catch (e: Exception) { Result.failure(APIError.NetworkError) }
    }

    suspend fun sendChatMedia(matchId: String, bytes: ByteArray, mimeType: String = "image/jpeg"): Result<Message> {
        return try {
            val body = bytes.toRequestBody(mimeType.toMediaTypeOrNull())
            val part = MultipartBody.Part.createFormData("media", "chat.jpg", body)
            val response = api.sendMedia(matchId, part)
            if (response.isSuccessful) Result.success(parseMessage(response.body()?.get("message") as? Map<*, *>))
            else Result.failure(APIError.ServerError)
        } catch (e: Exception) { Result.failure(APIError.NetworkError) }
    }

    // ──────────────────── FAMILY ────────────────────

    suspend fun fetchFamily(): Result<Pair<List<FamilyMember>, List<FamilySuggestion>>> {
        return try {
            val response = api.getFamily()
            if (response.isSuccessful) {
                val body = response.body() ?: return Result.success(Pair(emptyList(), emptyList()))
                val members = parseFamilyMembers(body["members"] as? List<*>)
                val suggestions = parseFamilySuggestions(body["suggestions"] as? List<*>)
                Result.success(Pair(members, suggestions))
            } else Result.failure(APIError.ServerError)
        } catch (e: Exception) { Result.failure(APIError.NetworkError) }
    }

    suspend fun generateInvite(): Result<FamilyInvite> {
        return try {
            val response = api.generateFamilyInvite()
            if (response.isSuccessful) {
                val body = response.body() ?: return Result.failure(APIError.ServerError)
                Result.success(FamilyInvite(
                    code = body["code"] as? String ?: "",
                    deepLink = body["deep_link"] as? String ?: "",
                    currentMembers = (body["current_members"] as? Number)?.toInt() ?: 0
                ))
            } else Result.failure(APIError.ServerError)
        } catch (e: Exception) { Result.failure(APIError.NetworkError) }
    }

    // ──────────────────── SAFETY ────────────────────

    suspend fun reportUser(userId: String, reason: String): Result<Boolean> {
        return try {
            val response = api.reportUser(mapOf("reported_user_id" to userId, "reason" to reason))
            Result.success(response.isSuccessful)
        } catch (e: Exception) { Result.failure(APIError.NetworkError) }
    }

    suspend fun blockUser(userId: String): Result<Boolean> {
        return try {
            val response = api.blockUser(mapOf("blocked_user_id" to userId))
            Result.success(response.isSuccessful)
        } catch (e: Exception) { Result.failure(APIError.NetworkError) }
    }

    // ──────────────────── PARSERS ────────────────────

    private fun parseUser(data: Map<*, *>?): User {
        if (data == null) return User(id = "", phone = "")
        return User(
            id = data["id"] as? String ?: "",
            phone = data["phone"] as? String ?: "",
            displayName = data["display_name"] as? String ?: "",
            dateOfBirth = (data["date_of_birth"] as? String)?.let { try { LocalDate.parse(it) } catch (e: Exception) { null } },
            gender = (data["gender"] as? String)?.let { g -> Gender.entries.firstOrNull { it.name.equals(g, true) } },
            bio = data["bio"] as? String ?: "",
            heightCm = (data["height_cm"] as? Number)?.toInt(),
            city = data["city"] as? String ?: "",
            state = data["state"] as? String ?: "",
            country = data["country"] as? String ?: "",
            intent = (data["intent"] as? String)?.let { i -> Intent.entries.firstOrNull { it.name.equals(i, true) } },
            isVerified = data["is_verified"] as? Boolean ?: false,
            photos = (data["photos"] as? List<*>)?.map { p ->
                val photo = p as? Map<*, *> ?: return@map UserPhoto(url = "")
                UserPhoto(
                    id = photo["id"] as? String ?: "",
                    url = photo["url_original"] as? String ?: photo["url"] as? String ?: "",
                    urlThumb = photo["url_thumb"] as? String,
                    urlMedium = photo["url_medium"] as? String,
                    isPrimary = photo["is_primary"] as? Boolean ?: false,
                    sortOrder = (photo["sort_order"] as? Number)?.toInt() ?: 0,
                    isVerified = photo["is_verified"] as? Boolean ?: false
                )
            } ?: emptyList(),
            occupation = data["occupation"] as? String,
            education = data["education"] as? String,
            company = data["company"] as? String,
            religion = data["religion"] as? String,
            sindhiFluency = (data["sindhi_fluency"] as? String)?.let { f -> SindhiFluency.entries.firstOrNull { it.name.equals(f, true) } },
            familyValues = (data["family_values"] as? String)?.let { f -> FamilyValues.entries.firstOrNull { it.name.equals(f, true) } },
            foodPreference = (data["food_preference"] as? String)?.let { f -> FoodPreference.entries.firstOrNull { it.name.equals(f, true) } },
            interests = (data["interests"] as? List<*>)?.mapNotNull { it as? String } ?: emptyList(),
            isOnline = data["is_online"] as? Boolean ?: false,
            profileCompleteness = (data["profile_completeness"] as? Number)?.toInt() ?: 0
        )
    }

    @Suppress("UNCHECKED_CAST")
    private fun parseFeedCards(data: List<*>?): List<FeedCard> {
        return data?.mapNotNull { item ->
            val card = item as? Map<*, *> ?: return@mapNotNull null
            val score = (card["cultural_score"] as? Number)?.toInt() ?: 0
            FeedCard(
                id = card["id"] as? String ?: "",
                user = parseUser(card),
                culturalScore = CulturalScore(
                    overallScore = score,
                    badge = when { score >= 85 -> CulturalBadge.GOLD; score >= 65 -> CulturalBadge.GREEN; score >= 40 -> CulturalBadge.ORANGE; else -> CulturalBadge.NONE }
                ),
                commonInterests = (card["common_interests"] as? Number)?.toInt() ?: 0,
                distanceKm = (card["distance_km"] as? Number)?.toDouble()
            )
        } ?: emptyList()
    }

    private fun parseLikes(data: List<*>?): List<LikedYouCard> {
        return data?.mapNotNull { item ->
            val like = item as? Map<*, *> ?: return@mapNotNull null
            val score = (like["cultural_score"] as? Number)?.toInt() ?: 0
            LikedYouCard(
                id = like["id"] as? String ?: "",
                user = parseUser(like["user"] as? Map<*, *>),
                culturalScore = score,
                culturalBadge = when { score >= 85 -> CulturalBadge.GOLD; score >= 65 -> CulturalBadge.GREEN; else -> CulturalBadge.ORANGE }
            )
        } ?: emptyList()
    }

    private fun parseMatches(data: List<*>?): List<Match> {
        return data?.mapNotNull { item -> parseMatch(item as? Map<*, *>) } ?: emptyList()
    }

    private fun parseMatch(data: Map<*, *>?): Match {
        if (data == null) return Match(otherUser = User(id = "", phone = ""))
        return Match(
            id = data["id"] as? String ?: "",
            otherUser = parseUser(data["other_user"] as? Map<*, *>),
            status = (data["status"] as? String)?.let { s -> MatchStatus.entries.firstOrNull { it.value == s } } ?: MatchStatus.PENDING_FIRST_MESSAGE,
            matchedAt = (data["matched_at"] as? Number)?.toLong() ?: System.currentTimeMillis(),
            expiresAt = (data["expires_at"] as? Number)?.toLong(),
            lastMessage = data["last_message"] as? String,
            unreadCount = (data["unread_count"] as? Number)?.toInt() ?: 0,
            firstMsgBy = data["first_msg_by"] as? String,
            firstMsgLocked = data["first_msg_locked"] as? Boolean ?: false,
            firstMsgAt = (data["first_msg_at"] as? Number)?.toLong()
        )
    }

    private fun parseMessages(data: List<*>?): List<Message> {
        return data?.mapNotNull { item -> parseMessage(item as? Map<*, *>) } ?: emptyList()
    }

    private fun parseMessage(data: Map<*, *>?): Message {
        if (data == null) return Message()
        return Message(
            id = data["id"] as? String ?: "",
            matchId = data["match_id"] as? String ?: "",
            senderId = data["sender_id"] as? String ?: "",
            content = data["content"] as? String ?: "",
            mediaUrl = data["media_url"] as? String,
            msgType = (data["msg_type"] as? String)?.let { t -> MessageType.entries.firstOrNull { it.value == t } } ?: MessageType.TEXT,
            status = if (data["is_read"] as? Boolean == true) MessageStatus.READ else MessageStatus.DELIVERED,
            createdAt = (data["created_at"] as? Number)?.toLong() ?: System.currentTimeMillis()
        )
    }

    private fun parseFamilyMembers(data: List<*>?): List<FamilyMember> {
        return data?.mapNotNull { item ->
            val m = item as? Map<*, *> ?: return@mapNotNull null
            val perms = m["permissions"] as? Map<*, *>
            FamilyMember(
                id = m["id"] as? String ?: "",
                name = m["name"] as? String ?: "",
                phone = m["phone"] as? String ?: "",
                relationship = m["role_tag"] as? String ?: "",
                status = (m["status"] as? String)?.let { s -> FamilyMemberStatus.entries.firstOrNull { it.value == s } } ?: FamilyMemberStatus.ACTIVE,
                permissions = FamilyPermissions(
                    canViewProfile = perms?.get("can_view_profile") as? Boolean ?: true,
                    canViewPhotos = perms?.get("can_view_photos") as? Boolean ?: true,
                    canViewBasics = perms?.get("can_view_basics") as? Boolean ?: true,
                    canViewSindhi = perms?.get("can_view_sindhi") as? Boolean ?: true,
                    canViewMatches = perms?.get("can_view_matches") as? Boolean ?: false,
                    canSuggest = perms?.get("can_suggest") as? Boolean ?: true,
                    canViewCulturalScore = perms?.get("can_view_cultural_score") as? Boolean ?: true,
                    canViewKundli = perms?.get("can_view_kundli") as? Boolean ?: false
                )
            )
        } ?: emptyList()
    }

    private fun parseFamilySuggestions(data: List<*>?): List<FamilySuggestion> {
        return data?.mapNotNull { item ->
            val s = item as? Map<*, *> ?: return@mapNotNull null
            FamilySuggestion(
                id = s["id"] as? String ?: "",
                suggestedBy = parseFamilyMembers(listOf(s["suggested_by"])).firstOrNull() ?: return@mapNotNull null,
                suggestedUser = parseUser(s["suggested_user"] as? Map<*, *>),
                note = s["note"] as? String
            )
        } ?: emptyList()
    }
}

sealed class APIError : Exception() {
    object InvalidOTP : APIError()
    object NetworkError : APIError()
    object Unauthorized : APIError()
    object RateLimited : APIError()
    object ServerError : APIError()
}
