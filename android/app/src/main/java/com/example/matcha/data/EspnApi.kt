package com.example.matcha.data

import com.example.matcha.data.espn.EspnEvent
import com.example.matcha.data.espn.EspnScoreboard
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/** Fetches and parses ESPN scoreboards into Matcha [Match] models. */
class EspnApi(
    private val json: Json = Json { ignoreUnknownKeys = true; coerceInputValues = true },
) {
    /** Fetch the given league's matches for a -3d..+5d window around now. */
    suspend fun fetchLeague(league: League): List<Match> = withContext(Dispatchers.IO) {
        val (start, end) = dynamicRange()
        val body = httpGet(league.scoreboardUrl(start, end)) ?: return@withContext emptyList()
        val board = runCatching { json.decodeFromString<EspnScoreboard>(body) }.getOrNull()
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
                setRequestProperty("User-Agent", "Matcha-Android")
            }
            if (conn.responseCode in 200..299) {
                conn.inputStream.bufferedReader().use { it.readText() }
            } else {
                null
            }
        } catch (_: Exception) {
            null
        } finally {
            conn?.disconnect()
        }
    }

    companion object {
        private val ESPN_DATE: SimpleDateFormat =
            SimpleDateFormat("yyyy-MM-dd'T'HH:mm'Z'", Locale.US).apply {
                timeZone = TimeZone.getTimeZone("UTC")
            }

        fun dynamicRange(now: Date = Date()): Pair<String, String> {
            val fmt = SimpleDateFormat("yyyyMMdd", Locale.US)
            val cal = Calendar.getInstance()
            cal.time = now
            cal.add(Calendar.DAY_OF_YEAR, -3)
            val start = fmt.format(cal.time)
            cal.time = now
            cal.add(Calendar.DAY_OF_YEAR, 5)
            val end = fmt.format(cal.time)
            return start to end
        }

        fun parseEpoch(date: String?): Long =
            date?.let { runCatching { ESPN_DATE.parse(it)?.time }.getOrNull() } ?: 0L
    }
}

private fun EspnEvent.toMatch(league: League): Match? {
    val comp = competitions.firstOrNull() ?: return null
    val competitors = comp.competitors
    val homeC = competitors.firstOrNull { it.homeAway == "home" } ?: competitors.getOrNull(0)
    val awayC = competitors.firstOrNull { it.homeAway == "away" } ?: competitors.getOrNull(1)
    if (homeC == null || awayC == null) return null

    val st = (status ?: comp.status)
    val state = when (st?.type?.state) {
        "in" -> MatchState.LIVE
        "post" -> MatchState.FINAL
        else -> MatchState.UPCOMING
    }
    val detail = st?.type?.shortDetail ?: st?.type?.detail ?: ""

    fun team(c: com.example.matcha.data.espn.EspnCompetitor): MatchTeam {
        val t = c.team
        return MatchTeam(
            name = t?.displayName ?: t?.name ?: "TBD",
            shortName = t?.shortDisplayName ?: t?.abbreviation ?: t?.displayName ?: "TBD",
            abbreviation = t?.abbreviation ?: t?.shortDisplayName ?: "",
            logoUrl = t?.logo,
            score = c.score,
            isWinner = c.winner == true,
            colorArgb = parseColor(t?.color),
            record = c.records.firstOrNull { it.type == "total" }?.summary
                ?: c.records.firstOrNull()?.summary,
            form = c.form,
        )
    }

    val broadcast = comp.broadcasts.firstOrNull()?.names?.firstOrNull()

    return Match(
        id = "${league.id}-$id",
        leagueId = league.id,
        leagueName = league.displayName,
        sport = league.sport,
        kickoffEpochMs = EspnApi.parseEpoch(date),
        home = team(homeC),
        away = team(awayC),
        state = state,
        statusDetail = detail,
        venue = comp.venue?.fullName,
        broadcast = broadcast,
    )
}

/** ESPN colors arrive as "RRGGBB" hex without a leading '#'. */
private fun parseColor(hex: String?): Long? {
    val clean = hex?.trim()?.removePrefix("#") ?: return null
    if (clean.length != 6) return null
    return runCatching { 0xFF000000L or clean.toLong(16) }.getOrNull()
}
