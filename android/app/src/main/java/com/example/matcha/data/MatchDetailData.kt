package com.example.matcha.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.net.HttpURLConnection
import java.net.URL

/** A single team-stat comparison row (Apple Sports split bar). */
data class StatComparison(
    val label: String,
    val home: String,
    val away: String,
    /** Home share of the total, 0f..1f, for the split bar. */
    val homeFraction: Float,
)

data class StandingRow(
    val teamName: String,
    val logoUrl: String?,
    val played: Int,
    val win: Int,
    val draw: Int,
    val loss: Int,
    val goalDiff: String,
    val points: Int,
    val highlight: Boolean,
)

data class StandingGroup(val name: String, val rows: List<StandingRow>)

data class MatchExtras(
    val stats: List<StatComparison> = emptyList(),
    val group: StandingGroup? = null,
)

/**
 * Fetches the richer detail data Apple Sports shows: team-stat comparisons
 * (from the ESPN match summary) and the relevant group table (from the ESPN
 * standings). Soccer only; best-effort.
 */
class EspnDetailApi(
    private val json: Json = Json { ignoreUnknownKeys = true; coerceInputValues = true },
) {
    suspend fun fetch(match: Match): MatchExtras = coroutineScope {
        if (match.sport != Sport.SOCCER) return@coroutineScope MatchExtras()
        val league = Leagues.byId(match.leagueId) ?: return@coroutineScope MatchExtras()
        val eventId = match.id.removePrefix("${match.leagueId}-")

        val statsDeferred = async(Dispatchers.IO) { fetchStats(league.slug, eventId) }
        val groupDeferred = async(Dispatchers.IO) { fetchGroup(league.slug, match) }
        MatchExtras(stats = statsDeferred.await(), group = groupDeferred.await())
    }

    private fun fetchStats(slug: String, eventId: String): List<StatComparison> {
        val url = "https://site.api.espn.com/apis/site/v2/sports/soccer/$slug/summary?event=$eventId"
        val body = httpGet(url) ?: return emptyList()
        val summary = runCatching { json.decodeFromString<Summary>(body) }.getOrNull() ?: return emptyList()
        val home = summary.boxscore.teams.firstOrNull { it.homeAway == "home" } ?: return emptyList()
        val away = summary.boxscore.teams.firstOrNull { it.homeAway == "away" } ?: return emptyList()
        val homeMap = home.statistics.associateBy { it.name }
        val awayMap = away.statistics.associateBy { it.name }

        return STAT_ORDER.mapNotNull { (key, label) ->
            val h = homeMap[key]?.displayValue ?: return@mapNotNull null
            val a = awayMap[key]?.displayValue ?: return@mapNotNull null
            StatComparison(label, h, a, fraction(h, a))
        }
    }

    private fun fetchGroup(slug: String, match: Match): StandingGroup? {
        val url = "https://site.api.espn.com/apis/v2/sports/soccer/$slug/standings"
        val body = httpGet(url) ?: return null
        val root = runCatching { json.decodeFromString<StandingsRoot>(body) }.getOrNull() ?: return null
        val terms = listOf(match.home.name, match.away.name).map { it.lowercase() }

        val group = root.children.firstOrNull { child ->
            child.standings.entries.any { e ->
                val n = (e.team.displayName ?: "").lowercase()
                terms.any { n.contains(it) || it.contains(n) }
            }
        } ?: return null

        val rows = group.standings.entries.map { e ->
            val n = (e.team.displayName ?: "").lowercase()
            StandingRow(
                teamName = e.team.displayName ?: "—",
                logoUrl = e.team.logos.firstOrNull()?.href,
                played = e.stat("gamesPlayed"),
                win = e.stat("wins"),
                draw = e.stat("ties"),
                loss = e.stat("losses"),
                goalDiff = e.statText("pointDifferential"),
                points = e.stat("points"),
                highlight = terms.any { n.contains(it) || it.contains(n) },
            )
        }
        return StandingGroup(group.name ?: "Group", rows)
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

    companion object {
        private val STAT_ORDER = listOf(
            "possessionPct" to "Possession %",
            "totalShots" to "Shots",
            "shotsOnTarget" to "Shots on Target",
            "wonCorners" to "Corners",
            "foulsCommitted" to "Fouls",
            "yellowCards" to "Yellow Cards",
            "offsides" to "Offsides",
        )

        private fun fraction(home: String, away: String): Float {
            val h = home.filter { it.isDigit() || it == '.' }.toFloatOrNull() ?: 0f
            val a = away.filter { it.isDigit() || it == '.' }.toFloatOrNull() ?: 0f
            val total = h + a
            return if (total <= 0f) 0.5f else (h / total)
        }
    }
}

// --- ESPN payload models (subset) ---------------------------------------

@Serializable
private data class Summary(val boxscore: Boxscore = Boxscore())

@Serializable
private data class Boxscore(val teams: List<BoxTeam> = emptyList())

@Serializable
private data class BoxTeam(
    val homeAway: String? = null,
    val statistics: List<BoxStat> = emptyList(),
)

@Serializable
private data class BoxStat(val name: String = "", val displayValue: String = "")

@Serializable
private data class StandingsRoot(val children: List<StandingsChild> = emptyList())

@Serializable
private data class StandingsChild(
    val name: String? = null,
    val standings: Standings = Standings(),
)

@Serializable
private data class Standings(val entries: List<StandingsEntry> = emptyList())

@Serializable
private data class StandingsEntry(
    val team: StandingsTeam = StandingsTeam(),
    val stats: List<StandingsStat> = emptyList(),
) {
    fun stat(name: String): Int =
        stats.firstOrNull { it.name == name }?.value?.toInt() ?: 0

    fun statText(name: String): String =
        stats.firstOrNull { it.name == name }?.displayValue ?: "0"
}

@Serializable
private data class StandingsTeam(
    val displayName: String? = null,
    val logos: List<StandingsLogo> = emptyList(),
)

@Serializable
private data class StandingsLogo(val href: String? = null)

@Serializable
private data class StandingsStat(
    val name: String = "",
    val displayValue: String = "",
    val value: Double = 0.0,
)
