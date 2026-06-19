package com.example.matcha.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

data class TeamSearchResult(
    val name: String,
    val sport: String,
    val league: String?,
    val logoUrl: String?,
)

/** Searches ESPN for teams across all sports to follow (Apple Sports discovery). */
class EspnSearchApi(
    private val json: Json = Json { ignoreUnknownKeys = true; coerceInputValues = true },
) {
    suspend fun searchTeams(query: String): List<TeamSearchResult> = withContext(Dispatchers.IO) {
        if (query.length < 2) return@withContext emptyList()
        val q = URLEncoder.encode(query, "UTF-8")
        val url = "https://site.web.api.espn.com/apis/common/v3/search?query=$q&limit=20&mode=prefix"
        val body = httpGet(url) ?: return@withContext emptyList()
        val res = runCatching { json.decodeFromString<Response>(body) }.getOrNull() ?: return@withContext emptyList()
        res.items
            .filter { it.type == "team" && it.displayName != null }
            .distinctBy { it.displayName }
            .take(15)
            .map { it.toResult() }
    }

    private fun httpGet(urlString: String): String? {
        var conn: HttpURLConnection? = null
        return try {
            conn = (URL(urlString).openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"; connectTimeout = 10_000; readTimeout = 10_000
                setRequestProperty("Accept", "application/json")
                setRequestProperty("User-Agent", "Matcha-Android")
            }
            if (conn.responseCode in 200..299) conn.inputStream.bufferedReader().use { it.readText() } else null
        } catch (_: Exception) {
            null
        } finally {
            conn?.disconnect()
        }
    }

    @Serializable private data class Response(val items: List<Item> = emptyList())

    @Serializable
    private data class Item(
        val id: String? = null,
        val displayName: String? = null,
        val type: String? = null,
        val sport: String? = null,
        val league: String? = null,
    ) {
        fun toResult() = TeamSearchResult(
            name = displayName!!,
            sport = sport ?: "",
            league = league,
            logoUrl = if (id != null && sport != null) {
                "https://a.espncdn.com/i/teamlogos/$sport/500/$id.png"
            } else null,
        )
    }
}
