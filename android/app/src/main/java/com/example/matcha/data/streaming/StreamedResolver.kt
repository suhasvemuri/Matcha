package com.example.matcha.data.streaming

import com.example.matcha.data.Match
import com.example.matcha.data.Sport
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import java.net.HttpURLConnection
import java.net.URL

/**
 * Android port of the macOS Streamed provider. Finds a streamed.st event
 * matching a Matcha [Match] and resolves its sources into openable
 * [StreamOption]s. Best-effort: returns an empty list rather than throwing.
 */
class StreamedResolver(
    private val json: Json = Json { ignoreUnknownKeys = true; coerceInputValues = true },
) {
    suspend fun resolve(match: Match): List<StreamOption> = withContext(Dispatchers.IO) {
        val base = BASES.firstOrNull { httpGet(it + matchPath(match, live = match.isLive)) != null }
            ?: BASES.first()

        val candidates = matchPaths(match).asSequence()
            .mapNotNull { httpGet(base + it) }
            .firstOrNull() ?: return@withContext emptyList()

        val matches = runCatching {
            json.decodeFromString<List<StreamedMatch>>(candidates)
        }.getOrDefault(emptyList())

        val event = bestMatch(matches, match) ?: return@withContext emptyList()

        event.sources.flatMap { source -> resolveSource(base, source) }
            .distinctBy { it.url }
            .ifEmpty { listOf(watchFallback(base, event)) }
    }

    private fun resolveSource(base: String, source: StreamedSource): List<StreamOption> {
        val paths = listOf(
            "/api/stream/${source.source}/${source.id}",
            "/api/streams/${source.source}/${source.id}",
        )
        val body = paths.asSequence().mapNotNull { httpGet(base + it) }.firstOrNull()
            ?: return emptyList()
        val streams = runCatching { json.decodeFromString<List<StreamedStream>>(body) }
            .getOrDefault(emptyList())
        return streams.mapNotNull { s ->
            val url = normalizeUrl(s.anyUrl, base) ?: return@mapNotNull null
            StreamOption(
                label = buildString {
                    append(source.source.replaceFirstChar { it.uppercase() })
                    if (s.hd == true) append(" · HD")
                    s.language?.takeIf { it.isNotBlank() }?.let { append(" · $it") }
                },
                url = url,
                source = source.source,
                isHd = s.hd == true,
                language = s.language,
            )
        }
    }

    private fun watchFallback(base: String, event: StreamedMatch): StreamOption =
        StreamOption(
            label = "Open on Streamed",
            url = "$base/watch/${event.id}",
            source = "streamed",
            isHd = false,
            language = null,
        )

    private fun bestMatch(matches: List<StreamedMatch>, target: Match): StreamedMatch? {
        val home = target.home.name.lowercase()
        val away = target.away.name.lowercase()
        return matches
            .map { it to score(it, home, away) }
            .filter { it.second > 0 }
            .maxByOrNull { it.second }
            ?.first
    }

    private fun score(candidate: StreamedMatch, home: String, away: String): Int {
        val hay = buildString {
            append(candidate.title.lowercase())
            candidate.teams?.home?.name?.let { append(" ").append(it.lowercase()) }
            candidate.teams?.away?.name?.let { append(" ").append(it.lowercase()) }
        }
        var s = 0
        if (containsTeam(hay, home)) s += 2
        if (containsTeam(hay, away)) s += 2
        return s
    }

    private fun containsTeam(hay: String, team: String): Boolean {
        if (team.isBlank()) return false
        if (hay.contains(team)) return true
        // Fall back to the most distinctive word (e.g. "Manchester" from "Manchester City").
        val token = team.split(" ").maxByOrNull { it.length } ?: return false
        return token.length >= 4 && hay.contains(token)
    }

    private fun matchPath(match: Match, live: Boolean): String =
        if (live) "/api/matches/live" else sportPath(match.sport)

    private fun matchPaths(match: Match): List<String> = buildList {
        if (match.isLive) add("/api/matches/live")
        add(sportPath(match.sport))
        add("/api/matches/all-today")
        add("/api/matches/all")
    }.distinct()

    private fun sportPath(sport: Sport): String = when (sport) {
        Sport.SOCCER -> "/api/matches/football"
        Sport.CRICKET -> "/api/matches/cricket"
    }

    private fun normalizeUrl(raw: String?, base: String): String? {
        val t = raw?.trim().orEmpty()
        if (t.isEmpty()) return null
        return when {
            t.startsWith("//") -> "https:$t"
            t.startsWith("http") -> t
            t.startsWith("/") -> base + t
            else -> null
        }
    }

    private fun httpGet(urlString: String): String? {
        var conn: HttpURLConnection? = null
        return try {
            conn = (URL(urlString).openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                connectTimeout = 10_000
                readTimeout = 10_000
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
        private val BASES = listOf("https://streamed.st", "https://streamed.pk")
    }
}
