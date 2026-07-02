package com.mitimaiti.app.services

import com.google.gson.GsonBuilder
import kotlinx.coroutines.runBlocking
import okhttp3.Interceptor
import okhttp3.OkHttpClient
import okhttp3.logging.HttpLoggingInterceptor
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import java.util.concurrent.TimeUnit

object HttpClient {
    private var tokenManager: TokenManager? = null

    fun init(tokenManager: TokenManager) {
        this.tokenManager = tokenManager
    }

    // Public auth endpoints — these mint a session and must never carry a stale
    // Bearer token. /auth/refresh in particular would short-circuit the
    // 401-retry loop below if it carried the same expired token it's trying to
    // replace.
    private val publicAuthPaths = setOf(
        "/v1/auth/login",
        "/v1/auth/verify",
        "/v1/auth/email/login",
        "/v1/auth/email/verify",
        "/v1/auth/google/verify",
        "/v1/auth/apple/verify",
        "/v1/auth/refresh",
    )

    private fun isPublicAuth(path: String): Boolean = path in publicAuthPaths

    private val authInterceptor = Interceptor { chain ->
        val originalRequest = chain.request()
        val isPublic = isPublicAuth(originalRequest.url.encodedPath)
        val token = if (isPublic) null else runBlocking { tokenManager?.getAccessToken() }
        val request = if (token != null) {
            originalRequest.newBuilder()
                .addHeader("Authorization", "Bearer $token")
                .addHeader("Content-Type", "application/json")
                .build()
        } else {
            originalRequest.newBuilder()
                .addHeader("Content-Type", "application/json")
                .build()
        }
        val response = chain.proceed(request)

        // Handle 401 — token expired. Skip on public auth endpoints; a 401
        // there means bad credentials, not a stale token.
        if (response.code == 401 && !isPublic) {
            response.close()
            val newToken = runBlocking { refreshToken() }
            if (newToken != null) {
                val retryRequest = originalRequest.newBuilder()
                    .addHeader("Authorization", "Bearer $newToken")
                    .addHeader("Content-Type", "application/json")
                    .build()
                return@Interceptor chain.proceed(retryRequest)
            }
        }
        response
    }

    private suspend fun refreshToken(): String? {
        val refreshToken = tokenManager?.getRefreshToken() ?: return null
        return try {
            val response = refreshApi.refreshToken(mapOf("refresh_token" to refreshToken))
            if (response.isSuccessful) {
                val body = response.body()
                val newAccess = body?.get("access_token") as? String
                val newRefresh = body?.get("refresh_token") as? String
                if (newAccess != null && newRefresh != null) {
                    tokenManager?.saveTokens(newAccess, newRefresh, tokenManager?.getUserId() ?: "")
                    newAccess
                } else null
            } else null
        } catch (e: Exception) { null }
    }

    private val loggingInterceptor = HttpLoggingInterceptor().apply {
        level = HttpLoggingInterceptor.Level.BODY
    }

    private val okHttpClient = OkHttpClient.Builder()
        .addInterceptor(authInterceptor)
        .addInterceptor(ResponseUnwrapInterceptor)
        .addInterceptor(loggingInterceptor)
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .writeTimeout(30, TimeUnit.SECONDS)
        .build()

    private val gson = GsonBuilder()
        .setDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'")
        // Explicit nulls must reach the backend: sending {"religion_filter":null}
        // is how a discovery filter gets CLEARED. Without this Gson drops null
        // map entries and filters could never be un-set.
        .serializeNulls()
        .create()

    val retrofit: Retrofit = Retrofit.Builder()
        .baseUrl(ApiConfig.BASE_URL)
        .client(okHttpClient)
        .addConverterFactory(GsonConverterFactory.create(gson))
        .build()

    // Separate retrofit for token refresh (no auth interceptor to avoid loops)
    private val refreshRetrofit: Retrofit = Retrofit.Builder()
        .baseUrl(ApiConfig.BASE_URL)
        .client(OkHttpClient.Builder()
            .addInterceptor(ResponseUnwrapInterceptor)
            .addInterceptor(loggingInterceptor)
            .connectTimeout(15, TimeUnit.SECONDS)
            .build())
        .addConverterFactory(GsonConverterFactory.create(gson))
        .build()

    private val refreshApi = refreshRetrofit.create(MitiMaitiApi::class.java)
}
