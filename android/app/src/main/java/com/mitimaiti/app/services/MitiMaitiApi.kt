package com.mitimaiti.app.services

import okhttp3.MultipartBody
import retrofit2.Response
import retrofit2.http.*

/**
 * Retrofit interface mapping to all MitiMaiti backend endpoints.
 * Mirrors: backend/src/routes/
 */
@JvmSuppressWildcards
interface MitiMaitiApi {

    // ──────────────────── AUTH (/v1/auth) ────────────────────

    @POST("auth/login")
    suspend fun sendOTP(@Body body: Map<String, String>): Response<Map<String, Any>>

    @POST("auth/verify")
    suspend fun verifyOTP(@Body body: Map<String, String>): Response<Map<String, Any>>

    @POST("auth/email/login")
    suspend fun sendEmailOTP(@Body body: Map<String, String>): Response<Map<String, Any>>

    @POST("auth/email/verify")
    suspend fun verifyEmailOTP(@Body body: Map<String, String>): Response<Map<String, Any>>

    @POST("auth/google/verify")
    suspend fun verifyGoogleIdToken(@Body body: Map<String, String>): Response<Map<String, Any>>

    @POST("auth/refresh")
    suspend fun refreshToken(@Body body: Map<String, String>): Response<Map<String, Any>>

    @POST("auth/delete")
    suspend fun deleteAccount(@Body body: Map<String, String>): Response<Map<String, Any>>

    // ──────────────────── PROFILE (/v1/me) ────────────────────

    @GET("me")
    suspend fun getProfile(): Response<Map<String, Any>>

    @PATCH("me")
    suspend fun updateProfile(@Body body: Map<String, Any>): Response<Map<String, Any>>

    @PATCH("me/basics")
    suspend fun updateBasics(@Body body: Map<String, Any>): Response<Map<String, Any>>

    @PATCH("me/sindhi")
    suspend fun updateSindhi(@Body body: Map<String, Any>): Response<Map<String, Any>>

    @PATCH("me/chatti")
    suspend fun updateChatti(@Body body: Map<String, Any>): Response<Map<String, Any>>

    @PATCH("me/personality")
    suspend fun updatePersonality(@Body body: Map<String, Any>): Response<Map<String, Any>>

    @PATCH("me/settings")
    suspend fun updateSettings(@Body body: Map<String, Any>): Response<Map<String, Any>>

    @Multipart
    @POST("me/verify")
    suspend fun verifySelfie(@Part selfie: MultipartBody.Part): Response<Map<String, Any>>

    @Multipart
    @POST("me/voice-intro")
    suspend fun uploadVoiceIntro(@Part audio: MultipartBody.Part): Response<Map<String, Any>>

    @DELETE("me/voice-intro")
    suspend fun deleteVoiceIntro(): Response<Map<String, Any>>

    @GET("me/export")
    suspend fun exportData(): Response<okhttp3.ResponseBody>

    @Multipart
    @POST("me/media")
    suspend fun uploadPhoto(@Part file: MultipartBody.Part): Response<Map<String, Any>>

    @DELETE("me/media/{id}")
    suspend fun deletePhoto(@Path("id") id: String): Response<Map<String, Any>>

    @PATCH("me/media/{id}/primary")
    suspend fun setPrimaryPhoto(@Path("id") id: String): Response<Map<String, Any>>

    @POST("me/media/reorder")
    suspend fun reorderPhotos(@Body body: Map<String, List<String>>): Response<Map<String, Any>>

    @POST("me/fcm-token")
    suspend fun registerFcmToken(@Body body: Map<String, String>): Response<Map<String, Any>>

    @GET("action/prompt")
    suspend fun getDailyPrompt(): Response<Map<String, Any>>

    // ──────────────────── DISCOVERY (/v1/feed) ────────────────────

    @GET("feed")
    suspend fun getFeed(
        @Query("cursor") cursor: String? = null,
        @Query("limit") limit: Int = 20
    ): Response<Map<String, Any>>

    @GET("feed/daily-pick")
    suspend fun getDailyPick(): Response<Map<String, Any>>

    @GET("feed/prompts")
    suspend fun getDailyPrompts(): Response<Map<String, Any>>

    // ──────────────────── ACTIONS (/v1/action) ────────────────────

    @POST("action")
    suspend fun performAction(@Body body: Map<String, String>): Response<Map<String, Any>>

    @POST("action/rewind")
    suspend fun rewind(): Response<Map<String, Any>>

    @POST("action/prompt")
    suspend fun answerPrompt(@Body body: Map<String, String>): Response<Map<String, Any>>

    // ──────────────────── INBOX (/v1/inbox) ────────────────────

    @GET("inbox")
    suspend fun getInbox(): Response<Map<String, Any>>

    // ──────────────────── CHAT (/v1/chat) ────────────────────

    @GET("chat/{matchId}")
    suspend fun getMessages(
        @Path("matchId") matchId: String,
        @Query("cursor") cursor: String? = null,
        @Query("limit") limit: Int = 50
    ): Response<Map<String, Any>>

    @POST("chat/{matchId}/messages")
    suspend fun sendMessage(
        @Path("matchId") matchId: String,
        @Body body: Map<String, String>
    ): Response<Map<String, Any>>

    @Multipart
    @POST("chat/{matchId}/media")
    suspend fun sendMedia(
        @Path("matchId") matchId: String,
        @Part media: MultipartBody.Part
    ): Response<Map<String, Any>>

    @Multipart
    @POST("chat/{matchId}/audio")
    suspend fun sendAudio(
        @Path("matchId") matchId: String,
        @Part audio: MultipartBody.Part,
        @Part("duration") duration: okhttp3.RequestBody
    ): Response<Map<String, Any>>

    @POST("chat/{matchId}/extend")
    suspend fun extendMatch(
        @Path("matchId") matchId: String
    ): Response<Map<String, Any>>

    @POST("chat/{matchId}/unmatch")
    suspend fun unmatch(
        @Path("matchId") matchId: String
    ): Response<Map<String, Any>>

    @PATCH("chat/{matchId}/messages/{messageId}")
    suspend fun editMessage(
        @Path("matchId") matchId: String,
        @Path("messageId") messageId: String,
        @Body body: Map<String, String>
    ): Response<Map<String, Any>>

    @DELETE("chat/{matchId}/messages/{messageId}")
    suspend fun deleteMessage(
        @Path("matchId") matchId: String,
        @Path("messageId") messageId: String
    ): Response<Map<String, Any>>

    @POST("chat/{matchId}/messages/{messageId}/reaction")
    suspend fun addReaction(
        @Path("matchId") matchId: String,
        @Path("messageId") messageId: String,
        @Body body: Map<String, String>
    ): Response<Map<String, Any>>

    @DELETE("chat/{matchId}/messages/{messageId}/reaction")
    suspend fun removeReaction(
        @Path("matchId") matchId: String,
        @Path("messageId") messageId: String
    ): Response<Map<String, Any>>

    // ──────────────────── FAMILY (/v1/family) ────────────────────

    @POST("family/invite")
    suspend fun generateFamilyInvite(): Response<Map<String, Any>>

    @POST("family/join")
    suspend fun joinFamily(@Body body: Map<String, String>): Response<Map<String, Any>>

    @GET("family")
    suspend fun getFamily(): Response<Map<String, Any>>

    @PATCH("family/{memberId}")
    suspend fun updateFamilyMember(
        @Path("memberId") memberId: String,
        @Body body: Map<String, Any>
    ): Response<Map<String, Any>>

    @POST("family/suggest")
    suspend fun suggestProfile(@Body body: Map<String, String>): Response<Map<String, Any>>

    @GET("family/feed")
    suspend fun getFamilyFeed(): Response<Map<String, Any>>

    @GET("family/suggestions")
    suspend fun getFamilySuggestions(): Response<Map<String, Any>>

    // ──────────────────── SAFETY (/v1/safety) ────────────────────

    @POST("safety/report")
    suspend fun reportUser(@Body body: Map<String, String>): Response<Map<String, Any>>

    @POST("safety/block")
    suspend fun blockUser(@Body body: Map<String, String>): Response<Map<String, Any>>

    @GET("safety/health")
    suspend fun getSafetyHealth(): Response<Map<String, Any>>

    @POST("safety/appeal")
    suspend fun appealStrike(@Body body: Map<String, String>): Response<Map<String, Any>>
}
