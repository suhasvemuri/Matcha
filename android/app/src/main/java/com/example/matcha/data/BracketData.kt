package com.example.matcha.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import java.net.HttpURLConnection
import java.net.URL

data class BracketTeam(val name: String, val logoUrl: String?, val score: String?, val winner: Boolean)
data class BracketMatch(val home: BracketTeam, val away: BracketTeam, val decided: Boolean)
data class BracketRound(val name: String, val matches: List<BracketMatch>)

/**
 * Builds a knockout bracket from ESPN fixtures. Each event's `season.slug`
 * identifies the round; placeholder fixtures (e.g. "Round of 32 1 Winner")
 * appear until the teams are determined.
 */
class EspnBracketApi(
    private val json: Json = Json { ignoreUnknownKeys = true; coerceInputValues = true },
) {
    suspend fun fetchBracket(league: League): List<BracketRound> = withContext(Dispatchers.IO) {
        if (league.espnSport != "soccer") return@withContext emptyList()
        // Pull the whole knockout window in one shot.
        val url = "https://site.api.espn.com/apis/site/v2/sports/soccer/${league.slug}/scoreboard?dates=$KNOCKOUT_WINDOW"
        val body = httpGet(url) ?: return@withContext emptyList()
        val board = runCatching { json.decodeFromString<ScoreboardWithSeason>(body) }.getOrNull()
            ?: return@withContext emptyList()

        val byRound = board.events
            .filter { it.season?.slug in ROUND_ORDER }
            .groupBy { it.season!!.slug!! }

        ROUND_ORDER.mapNotNull { slug ->
            val events = byRound[slug] ?: return@mapNotNull null
            val matches = events.sortedBy { it.date }.mapNotNull { it.toBracketMatch() }
            if (matches.isEmpty()) null else BracketRound(ROUND_LABELS[slug] ?: slug, matches)
        }
    }

    private fun httpGet(urlString: String): String? {
        var conn: HttpURLConnection? = null
        return try {
            conn = (URL(urlString).openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"; connectTimeout = 12_000; readTimeout = 12_000
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

    companion object {
        // 2026 World Cup knockout window (Round of 32 → Final).
        private const val KNOCKOUT_WINDOW = "20260628-20260720"
        private val ROUND_ORDER = listOf("round-of-32", "round-of-16", "quarterfinals", "semifinals", "final")
        private val ROUND_LABELS = mapOf(
            "round-of-32" to "Round of 32",
            "round-of-16" to "Round of 16",
            "quarterfinals" to "Quarterfinals",
            "semifinals" to "Semifinals",
            "final" to "Final",
        )
    }
}

private fun SeasonEvent.toBracketMatch(): BracketMatch? {
    val comp = competitions.firstOrNull() ?: return null
    val home = comp.competitors.firstOrNull { it.homeAway == "home" } ?: comp.competitors.getOrNull(0)
    val away = comp.competitors.firstOrNull { it.homeAway == "away" } ?: comp.competitors.getOrNull(1)
    if (home == null || away == null) return null
    val decided = (status ?: comp.status)?.type?.state == "post"
    fun team(c: com.example.matcha.data.espn.EspnCompetitor): BracketTeam {
        val t = c.team
        return BracketTeam(
            name = t?.shortDisplayName ?: t?.abbreviation ?: t?.displayName ?: "TBD",
            logoUrl = t?.logo,
            score = c.score,
            winner = c.winner == true,
        )
    }
    return BracketMatch(team(home), team(away), decided)
}

// Reuse the ESPN scoreboard shape but expose season.slug for round grouping.
@kotlinx.serialization.Serializable
private data class ScoreboardWithSeason(val events: List<SeasonEvent> = emptyList())

@kotlinx.serialization.Serializable
private data class SeasonEvent(
    val id: String = "",
    val date: String? = null,
    val name: String? = null,
    val season: EventSeason? = null,
    val status: com.example.matcha.data.espn.EspnStatus? = null,
    val competitions: List<com.example.matcha.data.espn.EspnCompetition> = emptyList(),
)

@kotlinx.serialization.Serializable
private data class EventSeason(val slug: String? = null)
