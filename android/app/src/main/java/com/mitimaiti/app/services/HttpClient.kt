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

    private val authInterceptor = Interceptor { chain ->
        val token = runBlocking { tokenManager?.getAccessToken() }
        val request = if (token != null) {
            chain.request().newBuilder()
                .addHeader("Authorization", "Bearer $token")
                .addHeader("Content-Type", "application/json")
                .build()
        } else {
            chain.request().newBuilder()
                .addHeader("Content-Type", "application/json")
                .build()
        }
        val response = chain.proceed(request)

        // Handle 401 — token expired
        if (response.code == 401) {
            response.close()
            val newToken = runBlocking { refreshToken() }
            if (newToken != null) {
                val retryRequest = chain.request().newBuilder()
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
            val response = refreshApi.refreshToken(mapOf("refreshToken" to refreshToken))
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
