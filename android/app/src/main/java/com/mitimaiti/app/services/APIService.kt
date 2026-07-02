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
            handleAuthVerifyResponse(response)
        } catch (e: Exception) { Result.failure(APIError.NetworkError) }
    }

    suspend fun sendEmailOTP(email: String): Result<Boolean> {
        return try {
            val response = api.sendEmailOTP(mapOf("email" to email))
            if (response.isSuccessful) Result.success(true)
            else Result.failure(APIError.ServerError)
        } catch (e: Exception) { Result.failure(APIError.NetworkError) }
    }

    suspend fun verifyEmailOTP(email: String, code: String): Result<Pair<User, Boolean>> {
        return try {
            val response = api.verifyEmailOTP(mapOf("email" to email, "token" to code))
            handleAuthVerifyResponse(response)
        } catch (e: Exception) { Result.failure(APIError.NetworkError) }
    }

    suspend fun verifyGoogleIdToken(idToken: String): Result<Pair<User, Boolean>> {
        return try {
            val response = api.verifyGoogleIdToken(mapOf("idToken" to idToken))
            handleAuthVerifyResponse(response)
        } catch (e: Exception) { Result.failure(APIError.NetworkError) }
    }

    /** GDPR data export: returns the raw JSON of everything the backend
     *  stores about the user (rate-limited to 2/hour server-side). */
    suspend fun exportData(): Result<String> {
        return try {
            val response = api.exportData()
            if (response.isSuccessful) {
                val raw = response.body()?.string()
                if (raw.isNullOrBlank()) Result.failure(APIError.ServerError)
                else Result.success(raw)
            } else if (response.code() == 429) Result.failure(APIError.DailyLimitReached)
            else Result.failure(APIError.ServerError)
        } catch (e: Exception) { Result.failure(APIError.NetworkError) }
    }

    /** Permanently delete the account server-side (soft-delete, 30-day window). */
    suspend fun deleteAccount(): Result<Boolean> {
        return try {
            val response = api.deleteAccount(mapOf("action" to "delete"))
            if (response.isSuccessful) Result.success(true) else Result.failure(APIError.ServerError)
        } catch (e: Exception) { Result.failure(APIError.NetworkError) }
    }

    private suspend fun handleAuthVerifyResponse(
        response: retrofit2.Response<Map<String, Any>>
    ): Result<Pair<User, Boolean>> {
        if (!response.isSuccessful) {
            return if (response.code() == 401) Result.failure(APIError.InvalidOTP)
            else Result.failure(APIError.ServerError)
        }
        val body = response.body() ?: return Result.failure(APIError.ServerError)
        val session = body["session"] as? Map<*, *>
        val userMap = body["user"] as? Map<*, *>
        val token = session?.get("access_token") as? String ?: ""
        val refresh = session?.get("refresh_token") as? String ?: ""
        val userId = userMap?.get("id") as? String ?: ""
        val isNew = userMap?.get("is_new") as? Boolean ?: false
        // Pre-seed the onboarding name field with the OAuth provider's name so
        // returning Google/Apple users don't have to retype it. Backend keys
        // it as camelCase `firstName`.
        (userMap?.get("first_name") as? String ?: userMap?.get("firstName") as? String)
            ?.takeIf { it.isNotBlank() }
            ?.let { UserPrefs.setFirstName(it) }
        setTokens(token, refresh)
        tokenManager?.saveTokens(token, refresh, userId)
        Message.currentUserId = userId
        SocketManager.shared.connect(token)
        return Result.success(Pair(parseUser(userMap), isNew))
    }

    // ──────────────────── PROFILE ────────────────────

    suspend fun fetchProfile(): Result<User> {
        return try {
            val response = api.getProfile()
            if (response.isSuccessful) {
                val user = parseUser(flattenMe(response.body()))
                // Session restore path: make sure message ownership checks know
                // who "me" is even when the auth verify flow didn't run.
                if (user.id.isNotEmpty()) Message.currentUserId = user.id
                Result.success(user)
            } else Result.failure(APIError.ServerError)
        } catch (e: Exception) { Result.failure(APIError.NetworkError) }
    }

    /**
     * GET /v1/me returns the profile split across sub-objects
     * ({ user, basics, sindhi, chatti, personality, settings, photos }),
     * whereas parseUser expects a single flat map (as returned by the auth
     * verify endpoints). Merge the sub-objects into one flat map. Each sub-table
     * carries its own `id`/`user_id` PKs, so merge `user` LAST — its authoritative
     * id / profile_completeness / needs_onboarding must win any collision — and
     * keep `photos` as the array parseUser looks for.
     */
    private fun flattenMe(body: Map<*, *>?): Map<*, *>? {
        if (body == null) return null
        // If the response is already flat (no known sub-objects), pass through.
        val hasSubObjects = listOf("user", "basics", "sindhi", "chatti", "personality", "settings")
            .any { body[it] is Map<*, *> }
        if (!hasSubObjects) return body
        val flat = mutableMapOf<Any?, Any?>()
        for (key in listOf("basics", "sindhi", "chatti", "personality", "settings", "user")) {
            (body[key] as? Map<*, *>)?.forEach { (k, v) -> if (v != null) flat[k] = v }
        }
        body["photos"]?.let { flat["photos"] = it }
        return flat
    }

    /** Raw user_settings row + user status flags from GET /v1/me, for the
     *  Settings screen to seed its state from the server instead of hardcoded
     *  defaults. */
    suspend fun fetchSettings(): Result<Map<String, Any?>> {
        return try {
            val response = api.getProfile()
            if (response.isSuccessful) {
                val body = response.body()
                val merged = mutableMapOf<String, Any?>()
                (body?.get("settings") as? Map<*, *>)?.forEach { (k, v) -> if (k is String) merged[k] = v }
                // is_snoozed lives on the users table
                (body?.get("user") as? Map<*, *>)?.get("is_snoozed")?.let { merged["is_snoozed"] = it }
                Result.success(merged)
            } else Result.failure(APIError.ServerError)
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
            } else if (response.code() == 400 && errorCodeOf(response) == "MAX_PHOTOS") {
                // Server's 6-photo cap — surface a typed error so onboarding can
                // treat it as non-fatal (mirrors iOS APIError.photoLimitReached).
                Result.failure(APIError.PhotoLimitReached)
            } else Result.failure(APIError.ServerError)
        } catch (e: Exception) { Result.failure(APIError.NetworkError) }
    }

    /** Read `error.code` from a non-2xx response body ({ success:false, error:{ code } }). */
    private fun errorCodeOf(response: retrofit2.Response<*>): String? = try {
        val raw = response.errorBody()?.string()
        if (raw.isNullOrBlank()) null
        else com.google.gson.JsonParser.parseString(raw).asJsonObject
            .getAsJsonObject("error")?.get("code")?.asString
    } catch (e: Exception) { null }

    data class VerifyResult(val verified: Boolean, val similarity: Int?, val message: String?)

    /** Selfie verification: the backend compares the selfie to the primary
     *  photo via AWS Rekognition. The selfie is never stored server-side.
     *  Max 3 attempts/day (429 after that). */
    suspend fun verifySelfie(bytes: ByteArray): Result<VerifyResult> {
        return try {
            val body = bytes.toRequestBody("image/jpeg".toMediaTypeOrNull())
            val part = MultipartBody.Part.createFormData("selfie", "selfie.jpg", body)
            val response = api.verifySelfie(part)
            if (response.isSuccessful) {
                // Success payload: { is_verified: true, similarity }. A failed
                // match also returns 200, but without is_verified.
                val b = response.body()
                val verified = b?.get("is_verified") as? Boolean ?: false
                Result.success(VerifyResult(
                    verified = verified,
                    similarity = (b?.get("similarity") as? Number)?.toInt(),
                    message = if (verified) null
                    else "The selfie didn't match your photo closely enough. Try better lighting and a clearer angle."
                ))
            } else if (response.code() == 429) {
                Result.failure(APIError.DailyLimitReached)
            } else {
                Result.failure(APIError.MessageRejected(when (errorCodeOf(response)) {
                    "NO_PRIMARY_PHOTO" -> "Add a profile photo before verifying."
                    "ALREADY_VERIFIED" -> "Your profile is already verified!"
                    "FACE_NOT_DETECTED" -> "Couldn't detect a face. Use a clear, well-lit selfie."
                    else -> "Verification failed. Please try again."
                }))
            }
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
            val response = api.joinFamily(mapOf("code" to code, "role_tag" to roleTag))
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

    /** One page of the discovery feed plus server-authoritative daily counters. */
    data class FeedPage(
        val cards: List<FeedCard>,
        val likesUsedToday: Int? = null,
        val rewindsUsedToday: Int? = null,
    )

    suspend fun fetchFeed(cursor: String? = null): Result<FeedPage> {
        return try {
            val response = api.getFeed(cursor)
            if (response.isSuccessful) {
                val body = response.body() ?: return Result.success(FeedPage(emptyList()))
                val limits = body["limits"] as? Map<*, *>
                Result.success(FeedPage(
                    cards = parseFeedCards(body["cards"] as? List<*>),
                    likesUsedToday = (limits?.get("likes_used_today") as? Number)?.toInt(),
                    rewindsUsedToday = (limits?.get("rewinds_used_today") as? Number)?.toInt(),
                ))
            } else Result.failure(APIError.ServerError)
        } catch (e: Exception) { Result.failure(APIError.NetworkError) }
    }

    /** "Most Compatible" daily pick — one card, stable for the day, or null
     *  when there's no candidate left. */
    suspend fun fetchDailyPick(): Result<FeedCard?> {
        return try {
            val response = api.getDailyPick()
            if (response.isSuccessful) {
                val card = response.body()?.get("card") as? Map<*, *>
                Result.success(card?.let { parseFeedCards(listOf(it)).firstOrNull() })
            } else Result.failure(APIError.ServerError)
        } catch (e: Exception) { Result.failure(APIError.NetworkError) }
    }

    // ──────────────────── ACTIONS ────────────────────

    data class ActionResult(
        val isMatch: Boolean,
        val matchId: String?,
        val likesUsedToday: Int? = null,
    )

    /** The backend responds with { is_match, match_id, likes_used_today, ... }. */
    suspend fun performAction(targetId: String, type: String): Result<ActionResult> {
        return try {
            val response = api.performAction(mapOf("target_user_id" to targetId, "type" to type))
            if (response.isSuccessful) {
                val body = response.body()
                Result.success(ActionResult(
                    isMatch = body?.get("is_match") as? Boolean ?: false,
                    matchId = body?.get("match_id") as? String,
                    likesUsedToday = (body?.get("likes_used_today") as? Number)?.toInt(),
                ))
            } else if (response.code() == 429) {
                Result.failure(APIError.DailyLimitReached)
            } else Result.failure(APIError.ServerError)
        } catch (e: Exception) { Result.failure(APIError.NetworkError) }
    }

    /** Undo the last swipe (like or pass). Fails with a message when the last
     *  like already became a match. */
    suspend fun rewind(): Result<Boolean> {
        return try {
            val response = api.rewind()
            if (response.isSuccessful) Result.success(true)
            else if (response.code() == 429) Result.failure(APIError.DailyLimitReached)
            else if (response.code() == 400 && errorCodeOf(response) == "CANNOT_REWIND_MATCHED") {
                Result.failure(APIError.CannotRewindMatched)
            } else Result.failure(APIError.ServerError)
        } catch (e: Exception) { Result.failure(APIError.NetworkError) }
    }

    // ──────────────────── INBOX ────────────────────

    suspend fun fetchInbox(): Result<Pair<List<LikedYouCard>, List<Match>>> {
        return try {
            val response = api.getInbox()
            if (response.isSuccessful) {
                val body = response.body() ?: return Result.success(Pair(emptyList(), emptyList()))
                // Backend shape: { liked_you: { count, profiles: [...] },
                //                  matches:   { count, profiles: [...] } }
                val likedYouObj = body["liked_you"] as? Map<*, *>
                val matchesObj = body["matches"] as? Map<*, *>
                val likes = parseLikes(likedYouObj?.get("profiles") as? List<*>)
                val matches = parseMatches(matchesObj?.get("profiles") as? List<*>)
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
            val senderId = tokenManager?.getUserId().toString()
            // Await the server ack — rejections (moderation, Respect-First lock,
            // rate limit) arrive only through it.
            val ack = kotlinx.coroutines.withTimeoutOrNull(10_000) {
                kotlinx.coroutines.suspendCancellableCoroutine<Pair<String?, String?>> { cont ->
                    SocketManager.shared.sendMessage(matchId, content, type.value) { _, error, messageId ->
                        if (cont.isActive) cont.resume(Pair(error, messageId), null)
                    }
                }
            }
            return when {
                // No ack within 10s — keep the optimistic bubble; the server
                // most likely got it and the socket was just slow.
                ack == null -> Result.success(Message(matchId = matchId, senderId = senderId, content = content, msgType = type, status = MessageStatus.SENT))
                ack.first != null -> Result.failure(APIError.MessageRejected(ack.first!!))
                else -> Result.success(Message(
                    id = ack.second ?: java.util.UUID.randomUUID().toString(),
                    matchId = matchId, senderId = senderId, content = content,
                    msgType = type, status = MessageStatus.SENT
                ))
            }
        }
        return try {
            val response = api.sendMessage(matchId, mapOf("content" to content, "type" to type.value))
            if (response.isSuccessful) Result.success(parseMessage(response.body()?.get("message") as? Map<*, *>))
            else Result.failure(APIError.ServerError)
        } catch (e: Exception) { Result.failure(APIError.NetworkError) }
    }

    /** Media/audio uploads return a FLAT payload:
     *  { message_id, msg_type, media_url, media_type, created_at[, duration_seconds] } */
    private fun parseMediaSendResponse(matchId: String, body: Map<*, *>?): Message {
        return Message(
            id = body?.get("message_id") as? String ?: java.util.UUID.randomUUID().toString(),
            matchId = matchId,
            senderId = Message.currentUserId ?: "current-user-id",
            mediaUrl = body?.get("media_url") as? String,
            msgType = (body?.get("msg_type") as? String)?.let { t -> MessageType.entries.firstOrNull { it.value == t } } ?: MessageType.PHOTO,
            status = MessageStatus.SENT,
            createdAt = parseTimestamp(body?.get("created_at")) ?: System.currentTimeMillis(),
            durationSeconds = (body?.get("duration_seconds") as? Number)?.toInt() ?: 0
        )
    }

    suspend fun sendChatMedia(matchId: String, bytes: ByteArray, mimeType: String = "image/jpeg"): Result<Message> {
        return try {
            val body = bytes.toRequestBody(mimeType.toMediaTypeOrNull())
            val part = MultipartBody.Part.createFormData("media", "chat.jpg", body)
            val response = api.sendMedia(matchId, part)
            if (response.isSuccessful) Result.success(parseMediaSendResponse(matchId, response.body()))
            else Result.failure(APIError.ServerError)
        } catch (e: Exception) { Result.failure(APIError.NetworkError) }
    }

    /** Upload a chat voice clip (m4a/AAC) with its duration in seconds. */
    suspend fun sendChatAudio(matchId: String, bytes: ByteArray, durationSeconds: Int): Result<Message> {
        return try {
            val body = bytes.toRequestBody("audio/mp4".toMediaTypeOrNull())
            val part = MultipartBody.Part.createFormData("audio", "voice.m4a", body)
            val durationBody = durationSeconds.toString().toRequestBody("text/plain".toMediaTypeOrNull())
            val response = api.sendAudio(matchId, part, durationBody)
            if (response.isSuccessful) Result.success(parseMediaSendResponse(matchId, response.body()))
            else Result.failure(APIError.ServerError)
        } catch (e: Exception) { Result.failure(APIError.NetworkError) }
    }

    /** Edit a text message. Backend appends the " [edited]" marker itself. */
    suspend fun editMessage(matchId: String, messageId: String, content: String): Result<Boolean> {
        return try {
            val response = api.editMessage(matchId, messageId, mapOf("content" to content))
            if (response.isSuccessful) Result.success(true) else Result.failure(APIError.ServerError)
        } catch (e: Exception) { Result.failure(APIError.NetworkError) }
    }

    /** Delete a message (sender-only, hard delete on the server). */
    suspend fun deleteMessage(matchId: String, messageId: String): Result<Boolean> {
        return try {
            val response = api.deleteMessage(matchId, messageId)
            if (response.isSuccessful) Result.success(true) else Result.failure(APIError.ServerError)
        } catch (e: Exception) { Result.failure(APIError.NetworkError) }
    }

    /** Dissolve a match (either participant can unmatch; irreversible). */
    suspend fun unmatch(matchId: String): Result<Boolean> {
        return try {
            val response = api.unmatch(matchId)
            if (response.isSuccessful) Result.success(true) else Result.failure(APIError.ServerError)
        } catch (e: Exception) { Result.failure(APIError.NetworkError) }
    }

    /** Add/replace the current user's reaction on a message. */
    suspend fun setReaction(matchId: String, messageId: String, emoji: String): Result<Boolean> {
        return try {
            val response = api.addReaction(matchId, messageId, mapOf("emoji" to emoji))
            if (response.isSuccessful) Result.success(true) else Result.failure(APIError.ServerError)
        } catch (e: Exception) { Result.failure(APIError.NetworkError) }
    }

    /** Remove the current user's reaction from a message. */
    suspend fun clearReaction(matchId: String, messageId: String): Result<Boolean> {
        return try {
            val response = api.removeReaction(matchId, messageId)
            if (response.isSuccessful) Result.success(true) else Result.failure(APIError.ServerError)
        } catch (e: Exception) { Result.failure(APIError.NetworkError) }
    }

    // ──────────────────── FAMILY ────────────────────

    suspend fun fetchFamily(): Result<Pair<List<FamilyMember>, List<FamilySuggestion>>> {
        return try {
            val response = api.getFamily()
            if (response.isSuccessful) {
                val body = response.body() ?: return Result.success(Pair(emptyList(), emptyList()))
                val members = parseFamilyMembers(body["members"] as? List<*>)
                // Suggestions live on a separate endpoint (GET /family/suggestions)
                val suggestions = try {
                    val sugResponse = api.getFamilySuggestions()
                    if (sugResponse.isSuccessful) {
                        parseFamilySuggestions(sugResponse.body()?.get("suggestions") as? List<*>)
                    } else emptyList()
                } catch (e: Exception) { emptyList() }
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

    /** Update a family member (permissions, is_revoked, or revoke_all). */
    suspend fun updateFamilyMember(memberId: String, body: Map<String, Any>): Result<Boolean> {
        return try {
            val response = api.updateFamilyMember(memberId, body)
            if (response.isSuccessful) Result.success(true) else Result.failure(APIError.ServerError)
        } catch (e: Exception) { Result.failure(APIError.NetworkError) }
    }

    // ──────────────────── SAFETY ────────────────────

    suspend fun reportUser(userId: String, reason: String): Result<Boolean> {
        return try {
            val response = api.reportUser(mapOf("reported_id" to userId, "reason" to reason))
            Result.success(response.isSuccessful)
        } catch (e: Exception) { Result.failure(APIError.NetworkError) }
    }

    suspend fun blockUser(userId: String): Result<Boolean> {
        return try {
            val response = api.blockUser(mapOf("blocked_id" to userId))
            Result.success(response.isSuccessful)
        } catch (e: Exception) { Result.failure(APIError.NetworkError) }
    }

    // ──────────────────── PARSERS ────────────────────

    /** Backend sends ISO-8601 strings for timestamps; some older paths sent epoch millis. */
    private fun parseTimestamp(value: Any?): Long? = when (value) {
        is Number -> value.toLong()
        is String -> try { java.time.Instant.parse(value).toEpochMilli() } catch (e: Exception) {
            try { java.time.OffsetDateTime.parse(value).toInstant().toEpochMilli() } catch (e2: Exception) { null }
        }
        else -> null
    }

    private fun parseCulturalBadge(value: Any?, score: Int): CulturalBadge =
        when ((value as? String)?.lowercase()) {
            "gold" -> CulturalBadge.GOLD
            "green", "great" -> CulturalBadge.GREEN
            "orange" -> CulturalBadge.ORANGE
            "none" -> CulturalBadge.NONE
            else -> when { score >= 85 -> CulturalBadge.GOLD; score >= 65 -> CulturalBadge.GREEN; score >= 40 -> CulturalBadge.ORANGE; else -> CulturalBadge.NONE }
        }

    private fun parseUser(data: Map<*, *>?): User {
        if (data == null) return User(id = "", phone = "")
        return User(
            id = data["id"] as? String ?: "",
            phone = data["phone"] as? String ?: "",
            email = data["email"] as? String,
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
            prompts = (data["prompts"] as? List<*>)?.mapNotNull { p ->
                val m = p as? Map<*, *> ?: return@mapNotNull null
                val q = m["question"] as? String ?: return@mapNotNull null
                val a = m["answer"] as? String ?: return@mapNotNull null
                UserPrompt(question = q, answer = a)
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
            profileCompleteness = (data["profile_completeness"] as? Number)?.toInt() ?: 0,
            needsOnboarding = data["needs_onboarding"] as? Boolean ?: false,
            // Feed/inbox cards send a computed `age` and no date_of_birth
            ageYears = (data["age"] as? Number)?.toInt()
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
            // Inbox liked_you items are FLAT cards (user fields at top level)
            LikedYouCard(
                id = like["id"] as? String ?: "",
                user = parseUser(like),
                culturalScore = score,
                culturalBadge = parseCulturalBadge(like["cultural_badge"], score),
                likedAt = parseTimestamp(like["liked_at"]) ?: System.currentTimeMillis()
            )
        } ?: emptyList()
    }

    private fun parseMatches(data: List<*>?): List<Match> {
        return data?.mapNotNull { item -> parseMatch(item as? Map<*, *>) } ?: emptyList()
    }

    private fun parseMatch(data: Map<*, *>?): Match {
        if (data == null) return Match(otherUser = User(id = "", phone = ""))
        // Inbox match items are FLAT: match_id, user_id, display_name, age,
        // city, is_verified, photo {url,url_thumb,url_medium}, ISO timestamps,
        // and last_message as an object {content, sent_at, is_you, msg_type}.
        val photo = data["photo"] as? Map<*, *>
        val otherUser = User(
            id = data["user_id"] as? String ?: "",
            displayName = data["display_name"] as? String ?: "",
            city = data["city"] as? String ?: "",
            isVerified = data["is_verified"] as? Boolean ?: false,
            ageYears = (data["age"] as? Number)?.toInt(),
            photos = photo?.let {
                listOf(UserPhoto(
                    url = it["url"] as? String ?: "",
                    urlThumb = it["url_thumb"] as? String,
                    urlMedium = it["url_medium"] as? String,
                    isPrimary = true
                ))
            } ?: emptyList()
        )
        val lastMsg = data["last_message"] as? Map<*, *>
        return Match(
            id = data["match_id"] as? String ?: data["id"] as? String ?: "",
            otherUser = otherUser,
            status = (data["status"] as? String)?.let { s -> MatchStatus.entries.firstOrNull { it.value == s } } ?: MatchStatus.PENDING_FIRST_MESSAGE,
            matchedAt = parseTimestamp(data["matched_at"]) ?: System.currentTimeMillis(),
            expiresAt = parseTimestamp(data["expires_at"]),
            lastMessage = lastMsg?.get("content") as? String,
            unreadCount = (data["unread_count"] as? Number)?.toInt() ?: 0,
            firstMsgBy = data["first_msg_by"] as? String,
            firstMsgByMe = data["first_msg_by_me"] as? Boolean ?: false,
            firstMsgLocked = data["first_msg_locked"] as? Boolean ?: false,
            firstMsgAt = parseTimestamp(data["first_msg_at"])
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
            createdAt = parseTimestamp(data["created_at"]) ?: parseTimestamp(data["sent_at"]) ?: System.currentTimeMillis()
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
            // Backend shape: { id, suggested_user_id, suggested_by: { user_id,
            // display_name }, suggested_profile: { display_name, city, country,
            // age, photo }, note, status, created_at }
            val by = s["suggested_by"] as? Map<*, *>
            val profile = s["suggested_profile"] as? Map<*, *>
            FamilySuggestion(
                id = s["id"] as? String ?: "",
                suggestedBy = FamilyMember(
                    id = by?.get("user_id") as? String ?: "",
                    name = by?.get("display_name") as? String ?: "Family Member"
                ),
                suggestedUser = User(
                    id = s["suggested_user_id"] as? String ?: "",
                    displayName = profile?.get("display_name") as? String ?: "",
                    city = profile?.get("city") as? String ?: "",
                    country = profile?.get("country") as? String ?: "",
                    ageYears = (profile?.get("age") as? Number)?.toInt(),
                    photos = (profile?.get("photo") as? String)?.let {
                        listOf(UserPhoto(url = it, urlThumb = it, isPrimary = true))
                    } ?: emptyList()
                ),
                note = s["note"] as? String,
                suggestedAt = parseTimestamp(s["created_at"]) ?: System.currentTimeMillis()
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
    /** Server's 6-photo cap (400 MAX_PHOTOS). Treated as non-fatal in onboarding. */
    object PhotoLimitReached : APIError()
    /** Server rejected a chat message (moderation, Respect-First lock, rate limit). */
    data class MessageRejected(val reason: String) : APIError()
    /** Daily like/rewind budget exhausted (429 DAILY_LIMIT_REACHED). */
    object DailyLimitReached : APIError()
    /** The last like already became a match — undo it via Unmatch instead. */
    object CannotRewindMatched : APIError()
}
