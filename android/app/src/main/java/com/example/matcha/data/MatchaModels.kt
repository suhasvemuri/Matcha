package com.example.matcha.data

/** UI-facing match state, collapsed from ESPN's status strings. */
enum class MatchState { UPCOMING, LIVE, FINAL }

/** One side of a match. */
data class MatchTeam(
    val name: String,
    val shortName: String,
    val abbreviation: String,
    val logoUrl: String?,
    val score: String?,
    val isWinner: Boolean,
)

/** A single match, decoupled from the ESPN payload shape. */
data class Match(
    val id: String,
    val leagueId: String,
    val leagueName: String,
    val sport: Sport,
    /** Epoch millis kickoff; 0 if unknown. Used for sorting. */
    val kickoffEpochMs: Long,
    val home: MatchTeam,
    val away: MatchTeam,
    val state: MatchState,
    /** e.g. "45'", "HT", "Final", "Today 7:00 PM". */
    val statusDetail: String,
    val venue: String?,
) {
    val isLive: Boolean get() = state == MatchState.LIVE
}

/** A league plus the matches currently in its window. */
data class LeagueMatches(
    val league: League,
    val matches: List<Match>,
)
