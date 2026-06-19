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

/** A starting XI laid out by formation for the pitch graphic. */
data class FormationPlayer(
    val name: String,
    val jersey: String,
    val line: Int,        // 0 = GK, 1 = defenders, ... up the pitch
    val indexInLine: Int,
    val lineCount: Int,
)

data class TeamFormation(
    val teamName: String,
    val formation: String,
    val players: List<FormationPlayer>,
)

/** A goal in the match timeline. */
data class GoalEvent(val minute: String, val scorer: String, val isHome: Boolean)

data class MatchExtras(
    val stats: List<StatComparison> = emptyList(),
    val group: StandingGroup? = null,
    val homeFormation: TeamFormation? = null,
    val awayFormation: TeamFormation? = null,
    val goals: List<GoalEvent> = emptyList(),
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

        val summaryDeferred = async(Dispatchers.IO) { fetchSummary(league.slug, eventId, match) }
        val groupDeferred = async(Dispatchers.IO) { fetchGroup(league.slug, match) }
        val summary = summaryDeferred.await()
        MatchExtras(
            stats = summary?.stats ?: emptyList(),
            group = groupDeferred.await(),
            homeFormation = summary?.homeFormation,
            awayFormation = summary?.awayFormation,
            goals = summary?.goals ?: emptyList(),
        )
    }

    private class SummaryData(
        val stats: List<StatComparison>,
        val homeFormation: TeamFormation?,
        val awayFormation: TeamFormation?,
        val goals: List<GoalEvent>,
    )

    private fun fetchSummary(
        slug: String,
        eventId: String,
        match: Match,
    ): SummaryData? {
        val url = "https://site.api.espn.com/apis/site/v2/sports/soccer/$slug/summary?event=$eventId"
        val body = httpGet(url) ?: return null
        val summary = runCatching { json.decodeFromString<Summary>(body) }.getOrNull() ?: return null

        val home = summary.boxscore.teams.firstOrNull { it.homeAway == "home" }
        val away = summary.boxscore.teams.firstOrNull { it.homeAway == "away" }
        val stats = if (home != null && away != null) {
            val homeMap = home.statistics.associateBy { it.name }
            val awayMap = away.statistics.associateBy { it.name }
            STAT_ORDER.mapNotNull { (key, label) ->
                val h = homeMap[key]?.displayValue ?: return@mapNotNull null
                val a = awayMap[key]?.displayValue ?: return@mapNotNull null
                StatComparison(label, h, a, fraction(h, a))
            }
        } else emptyList()

        // Map the two rosters to home/away by team name.
        val homeName = match.home.name.lowercase()
        val homeRoster = summary.rosters.firstOrNull { (it.team.displayName ?: "").lowercase() == homeName }
            ?: summary.rosters.getOrNull(0)
        val awayRoster = summary.rosters.firstOrNull { it !== homeRoster }

        val goals = summary.keyEvents
            .filter { it.scoringPlay == true || it.type?.text == "Goal" }
            .mapNotNull { ev ->
                val scorer = ev.participants.firstOrNull()?.athlete?.displayName ?: return@mapNotNull null
                GoalEvent(
                    minute = ev.clock?.displayValue.orEmpty(),
                    scorer = scorer,
                    isHome = (ev.team?.displayName ?: "").lowercase() == homeName,
                )
            }

        return SummaryData(stats, homeRoster?.toFormation(), awayRoster?.toFormation(), goals)
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
private data class Summary(
    val boxscore: Boxscore = Boxscore(),
    val rosters: List<Roster> = emptyList(),
    val keyEvents: List<KeyEvent> = emptyList(),
)

@Serializable
private data class KeyEvent(
    val type: KeyEventType? = null,
    val scoringPlay: Boolean? = null,
    val clock: KeyEventClock? = null,
    val team: BoxTeamInfo? = null,
    val participants: List<KeyEventParticipant> = emptyList(),
)

@Serializable
private data class KeyEventType(val text: String? = null)

@Serializable
private data class KeyEventClock(val displayValue: String? = null)

@Serializable
private data class KeyEventParticipant(val athlete: Athlete? = null)

@Serializable
private data class Roster(
    val homeAway: String? = null,
    val formation: String? = null,
    val team: BoxTeamInfo = BoxTeamInfo(),
    val roster: List<RosterPlayer> = emptyList(),
) {
    fun toFormation(): TeamFormation? {
        val f = formation ?: return null
        val starters = roster.filter { it.starter == true }.sortedBy { it.formationPlace ?: 99 }
        if (starters.size < 11) return null
        val lines = listOf(1) + f.split("-").mapNotNull { it.toIntOrNull() } // GK + outfield
        val players = mutableListOf<FormationPlayer>()
        var idx = 0
        for ((lineIdx, count) in lines.withIndex()) {
            for (i in 0 until count) {
                val p = starters.getOrNull(idx) ?: break
                players.add(
                    FormationPlayer(
                        name = p.athlete?.shortName ?: p.athlete?.displayName.orEmpty(),
                        jersey = p.athlete?.jersey.orEmpty(),
                        line = lineIdx,
                        indexInLine = i,
                        lineCount = count,
                    ),
                )
                idx++
            }
        }
        return TeamFormation(team.displayName.orEmpty(), f, players)
    }
}

@Serializable
private data class BoxTeamInfo(val displayName: String? = null)

@Serializable
private data class RosterPlayer(
    val starter: Boolean? = null,
    val formationPlace: Int? = null,
    val athlete: Athlete? = null,
)

@Serializable
private data class Athlete(
    val displayName: String? = null,
    val shortName: String? = null,
    val jersey: String? = null,
)

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
