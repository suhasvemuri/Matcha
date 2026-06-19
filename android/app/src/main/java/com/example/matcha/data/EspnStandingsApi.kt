package com.example.matcha.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.net.HttpURLConnection
import java.net.URL

/**
 * Full competition standings (all groups, or a single league table) for the
 * scores feed — Apple Sports shows these below the matches.
 */
class EspnStandingsApi(
    private val json: Json = Json { ignoreUnknownKeys = true; coerceInputValues = true },
) {
    suspend fun fetchAll(league: League): List<StandingGroup> = withContext(Dispatchers.IO) {
        if (league.espnSport != "soccer") return@withContext emptyList()
        val url = "https://site.api.espn.com/apis/v2/sports/soccer/${league.slug}/standings"
        val body = httpGet(url) ?: return@withContext emptyList()
        val root = runCatching { json.decodeFromString<Root>(body) }.getOrNull() ?: return@withContext emptyList()

        val groups = if (root.children.isNotEmpty()) {
            root.children.map { it.name.orEmpty() to it.standings.entries }
        } else {
            listOf((root.name ?: "Standings") to root.standings.entries)
        }
        groups.mapNotNull { (name, entries) ->
            if (entries.isEmpty()) return@mapNotNull null
            StandingGroup(name, entries.map { it.toRow() })
        }
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

    @Serializable
    private data class Root(
        val name: String? = null,
        val children: List<Child> = emptyList(),
        val standings: Standings = Standings(),
    )

    @Serializable private data class Child(val name: String? = null, val standings: Standings = Standings())
    @Serializable private data class Standings(val entries: List<Entry> = emptyList())

    @Serializable
    private data class Entry(val team: Team = Team(), val stats: List<Stat> = emptyList()) {
        fun toRow() = StandingRow(
            teamName = team.displayName ?: "—",
            logoUrl = team.logos.firstOrNull()?.href,
            played = stat("gamesPlayed"),
            win = stat("wins"),
            draw = stat("ties"),
            loss = stat("losses"),
            goalDiff = statText("pointDifferential"),
            points = stat("points"),
            highlight = false,
        )
        private fun stat(n: String) = stats.firstOrNull { it.name == n }?.value?.toInt() ?: 0
        private fun statText(n: String) = stats.firstOrNull { it.name == n }?.displayValue ?: "0"
    }

    @Serializable private data class Team(val displayName: String? = null, val logos: List<Logo> = emptyList())
    @Serializable private data class Logo(val href: String? = null)
    @Serializable private data class Stat(val name: String = "", val displayValue: String = "", val value: Double = 0.0)
}
