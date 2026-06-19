package com.example.matcha.data.espn

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Minimal serializable mirror of ESPN's public `site.api.espn.com`
 * scoreboard payload. Only the fields Matcha renders are modeled; the JSON
 * parser is configured with `ignoreUnknownKeys` so the rest is dropped.
 */
@Serializable
data class EspnScoreboard(
    val events: List<EspnEvent> = emptyList(),
    val leagues: List<EspnLeague> = emptyList(),
)

@Serializable
data class EspnLeague(
    val name: String? = null,
    val abbreviation: String? = null,
)

@Serializable
data class EspnEvent(
    val id: String = "",
    val date: String? = null,
    val name: String? = null,
    val shortName: String? = null,
    val status: EspnStatus? = null,
    val competitions: List<EspnCompetition> = emptyList(),
)

@Serializable
data class EspnCompetition(
    val competitors: List<EspnCompetitor> = emptyList(),
    val venue: EspnVenue? = null,
    val status: EspnStatus? = null,
    val broadcasts: List<EspnBroadcast> = emptyList(),
)

@Serializable
data class EspnBroadcast(
    val names: List<String> = emptyList(),
)

@Serializable
data class EspnVenue(
    val fullName: String? = null,
)

@Serializable
data class EspnCompetitor(
    val id: String = "",
    val homeAway: String? = null,
    val score: String? = null,
    val winner: Boolean? = null,
    val form: String? = null,
    val records: List<EspnRecord> = emptyList(),
    val team: EspnTeam? = null,
)

@Serializable
data class EspnRecord(
    val type: String? = null,
    val summary: String? = null,
)

@Serializable
data class EspnTeam(
    val displayName: String? = null,
    val shortDisplayName: String? = null,
    val name: String? = null,
    val abbreviation: String? = null,
    val logo: String? = null,
    val color: String? = null,
    val alternateColor: String? = null,
)

@Serializable
data class EspnStatus(
    val displayClock: String? = null,
    val period: Int? = null,
    val type: EspnStatusType? = null,
)

@Serializable
data class EspnStatusType(
    val state: String? = null, // "pre" | "in" | "post"
    val completed: Boolean? = null,
    val detail: String? = null,
    @SerialName("shortDetail") val shortDetail: String? = null,
)
