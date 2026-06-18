package com.example.matcha.wear.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

/**
 * Standalone score fetcher for the watch. Mirrors the phone app's ESPN data
 * layer in a single self-contained file so the Wear module needs no shared
 * module. Favorites sync from the phone is a future enhancement; for now the
 * watch shows a curated default set led by the FIFA World Cup.
 */

enum class WearMatchState { UPCOMING, LIVE, FINAL }

data class WearMatch(
    val id: String,
    val leagueName: String,
    val homeName: String,
    val homeScore: String?,
    val awayName: String,
    val awayScore: String?,
    val state: WearMatchState,
    val statusDetail: String,
)

data class WearLeague(val name: String, val slug: String, val espnSport: String = "soccer")

object WearLeagues {
    val defaults = listOf(
        WearLeague("FIFA World Cup", "fifa.world"),
        WearLeague("Premier League", "ENG.1"),
        WearLeague("Champions League", "uefa.champions"),
        WearLeague("IPL", "8048", "cricket"),
    )

    /** Decodes `espnSport|slug|displayName` strings synced from the phone. */
    fun decode(encoded: Collection<String>): List<WearLeague> =
        encoded.mapNotNull { line ->
            val parts = line.split("|")
            if (parts.size >= 3) WearLeague(parts[2], parts[1], parts[0]) else null
        }
}

class WearScoresApi(
    private val json: Json = Json { ignoreUnknownKeys = true; coerceInputValues = true },
) {
    /** Fetch favorites synced from the phone, or the curated defaults. */
    suspend fun fetchFavorites(leagues: List<WearLeague>): List<WearMatch> = coroutineScope {
        leagues.ifEmpty { WearLeagues.defaults }
            .map { async(Dispatchers.IO) { fetchLeague(it) } }
            .awaitAll()
            .flatten()
            .sortedWith(compareBy({ it.state.order }, { it.id }))
    }

    suspend fun fetchDefaults(): List<WearMatch> = fetchFavorites(WearLeagues.defaults)

    private suspend fun fetchLeague(league: WearLeague): List<WearMatch> = withContext(Dispatchers.IO) {
        val (start, end) = range()
        val url = "https://site.api.espn.com/apis/site/v2/sports/${league.espnSport}/${league.slug}/scoreboard?dates=$start-$end"
        val body = httpGet(url) ?: return@withContext emptyList()
        val board = runCatching { json.decodeFromString<Scoreboard>(body) }.getOrNull()
            ?: return@withContext emptyList()
        board.events.mapNotNull { it.toMatch(league) }
    }

    private fun httpGet(urlString: String): String? {
        var conn: HttpURLConnection? = null
        return try {
            conn = (URL(urlString).openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                connectTimeout = 12_000
                readTimeout = 12_000
                setRequestProperty("Accept", "application/json")
                setRequestProperty("User-Agent", "Matcha-Wear")
            }
            if (conn.responseCode in 200..299) conn.inputStream.bufferedReader().use { it.readText() } else null
        } catch (_: Exception) {
            null
        } finally {
            conn?.disconnect()
        }
    }

    private fun range(): Pair<String, String> {
        val fmt = SimpleDateFormat("yyyyMMdd", Locale.US)
        val cal = Calendar.getInstance()
        cal.add(Calendar.DAY_OF_YEAR, -2)
        val start = fmt.format(cal.time)
        cal.add(Calendar.DAY_OF_YEAR, 6)
        return start to fmt.format(cal.time)
    }
}

@Serializable
private data class Scoreboard(val events: List<Event> = emptyList())

@Serializable
private data class Event(
    val id: String = "",
    val status: Status? = null,
    val competitions: List<Competition> = emptyList(),
)

@Serializable
private data class Competition(val competitors: List<Competitor> = emptyList(), val status: Status? = null)

@Serializable
private data class Competitor(
    val homeAway: String? = null,
    val score: String? = null,
    val team: Team? = null,
)

@Serializable
private data class Team(
    val displayName: String? = null,
    val shortDisplayName: String? = null,
    val abbreviation: String? = null,
)

@Serializable
private data class Status(val type: StatusType? = null)

@Serializable
private data class StatusType(
    val state: String? = null,
    @SerialName("shortDetail") val shortDetail: String? = null,
)

private val WearMatchState.order: Int
    get() = when (this) {
        WearMatchState.LIVE -> 0
        WearMatchState.UPCOMING -> 1
        WearMatchState.FINAL -> 2
    }

private fun Event.toMatch(league: WearLeague): WearMatch? {
    val comp = competitions.firstOrNull() ?: return null
    val home = comp.competitors.firstOrNull { it.homeAway == "home" } ?: comp.competitors.getOrNull(0)
    val away = comp.competitors.firstOrNull { it.homeAway == "away" } ?: comp.competitors.getOrNull(1)
    if (home == null || away == null) return null
    val st = status ?: comp.status
    val state = when (st?.type?.state) {
        "in" -> WearMatchState.LIVE
        "post" -> WearMatchState.FINAL
        else -> WearMatchState.UPCOMING
    }
    fun name(c: Competitor) =
        c.team?.shortDisplayName ?: c.team?.abbreviation ?: c.team?.displayName ?: "TBD"
    return WearMatch(
        id = "${league.slug}-$id",
        leagueName = league.name,
        homeName = name(home),
        homeScore = home.score,
        awayName = name(away),
        awayScore = away.score,
        state = state,
        statusDetail = st?.type?.shortDetail ?: "",
    )
}
