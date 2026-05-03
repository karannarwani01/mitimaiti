package com.mitimaiti.app.services

import com.google.gson.Gson
import com.google.gson.JsonArray
import com.google.gson.JsonElement
import com.google.gson.JsonObject
import okhttp3.Interceptor
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody

object ResponseUnwrapInterceptor : Interceptor {
    private val gson = Gson()
    private val camelToSnake = Regex("([a-z0-9])([A-Z])")

    override fun intercept(chain: Interceptor.Chain): Response {
        val response = chain.proceed(chain.request())
        if (!response.isSuccessful) return response
        val body = response.body ?: return response
        val mediaType = body.contentType()
        if (mediaType?.subtype != "json") return response

        val raw = body.string()
        val transformed = try {
            val root = gson.fromJson(raw, JsonElement::class.java)
            if (root.isJsonObject) {
                val obj = root.asJsonObject
                val unwrapped: JsonElement = if (obj.has("success") && obj.has("data")) obj.get("data") else obj
                gson.toJson(convertKeys(unwrapped))
            } else {
                raw
            }
        } catch (e: Exception) {
            raw
        }

        val newBody = transformed.toResponseBody(mediaType)
        return response.newBuilder().body(newBody).build()
    }

    private fun convertKeys(elem: JsonElement): JsonElement {
        if (elem.isJsonObject) {
            val obj = elem.asJsonObject
            val out = JsonObject()
            for ((k, v) in obj.entrySet()) out.add(toSnake(k), convertKeys(v))
            return out
        }
        if (elem.isJsonArray) {
            val arr = JsonArray()
            for (item in elem.asJsonArray) arr.add(convertKeys(item))
            return arr
        }
        return elem
    }

    private fun toSnake(s: String): String =
        camelToSnake.replace(s) { "${it.groupValues[1]}_${it.groupValues[2]}" }.lowercase()
}
