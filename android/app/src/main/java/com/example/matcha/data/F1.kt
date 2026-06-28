package com.example.matcha.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.net.HttpURLConnection
import java.net.URL

data class DriverResult(val position: Int, val driver: String, val team: String?)

data class RaceEvent(
    val id: String,
    val name: String,
    val circuit: String?,
    val statusDetail: String,
    val state: MatchState,
    val results: List<DriverResult>,
)

/** Formula 1 races from ESPN (racing/f1). Different shape from team sports. */
class EspnF1Api(
    private val json: Json = Json { ignoreUnknownKeys = true; coerceInputValues = true },
) {
    suspend fun fetchRaces(): List<RaceEvent> = withContext(Dispatchers.IO) {
        val body = httpGet("https://site.api.espn.com/apis/site/v2/sports/racing/f1/scoreboard")
            ?: return@withContext emptyList()
        val board = runCatching { json.decodeFromString<Board>(body) }.getOrNull()
            ?: return@withContext emptyList()
        board.events.map { it.toRace() }
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

    @Serializable private data class Board(val events: List<Event> = emptyList())

    @Serializable
    private data class Event(
        val id: String = "",
        val name: String = "",
        val status: Status? = null,
        val competitions: List<Competition> = emptyList(),
    ) {
        fun toRace(): RaceEvent {
            val comp = competitions.firstOrNull()
            val st = status ?: comp?.status
            val state = when (st?.type?.state) {
                "in" -> MatchState.LIVE
                "post" -> MatchState.FINAL
                else -> MatchState.UPCOMING
            }
            val results = comp?.competitors.orEmpty()
                .sortedBy { it.order ?: 99 }
                .mapNotNull { c ->
                    val d = c.athlete?.displayName ?: return@mapNotNull null
                    DriverResult(c.order ?: 0, d, c.vehicle?.manufacturer ?: c.team?.displayName)
                }
            return RaceEvent(
                id = id,
                name = name,
                circuit = comp?.venue?.fullName,
                statusDetail = st?.type?.shortDetail ?: "",
                state = state,
                results = results,
            )
        }
    }

    @Serializable private data class Competition(
        val venue: Venue? = null,
        val status: Status? = null,
        val competitors: List<Competitor> = emptyList(),
    )
    @Serializable private data class Venue(val fullName: String? = null)
    @Serializable private data class Competitor(
        val order: Int? = null,
        val athlete: Athlete? = null,
        val team: Team? = null,
        val vehicle: Vehicle? = null,
    )
    @Serializable private data class Athlete(val displayName: String? = null)
    @Serializable private data class Team(val displayName: String? = null)
    @Serializable private data class Vehicle(val manufacturer: String? = null)
    @Serializable private data class Status(val type: StatusType? = null)
    @Serializable private data class StatusType(val state: String? = null, val shortDetail: String? = null)
}
