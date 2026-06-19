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
        val base = BASES.firstOrNull { httpGet("$it/api/matches/all-today") != null }
            ?: BASES.first()

        // Search across every relevant endpoint and pool the candidates — the
        // match might be listed under live, the sport, or the day, with
        // differing coverage. Dedupe by id, then pick the best name match.
        val pooled = LinkedHashMap<String, StreamedMatch>()
        for (path in matchPaths(match)) {
            val body = httpGet(base + path) ?: continue
            runCatching { json.decodeFromString<List<StreamedMatch>>(body) }
                .getOrDefault(emptyList())
                .forEach { pooled.putIfAbsent(it.id.ifBlank { it.title }, it) }
        }

        val event = bestMatch(pooled.values.toList(), match) ?: return@withContext emptyList()

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

    internal fun bestMatch(matches: List<StreamedMatch>, target: Match): StreamedMatch? {
        val category = sportCategory(target.sport)
        val homeTokens = tokens(target.home.name)
        val awayTokens = tokens(target.away.name)
        return matches
            // Prefer same-sport candidates, but don't hard-require it.
            .map { it to score(it, homeTokens, awayTokens, category) }
            .filter { it.second >= 2 }
            .maxByOrNull { it.second }
            ?.first
    }

    private fun score(
        candidate: StreamedMatch,
        homeTokens: List<String>,
        awayTokens: List<String>,
        category: String,
    ): Int {
        val hay = normalize(
            buildString {
                append(candidate.title)
                candidate.teams?.home?.name?.let { append(" ").append(it) }
                candidate.teams?.away?.name?.let { append(" ").append(it) }
            },
        )
        var s = 0
        if (matchesTeam(hay, homeTokens)) s += 2
        if (matchesTeam(hay, awayTokens)) s += 2
        if (s > 0 && candidate.category.equals(category, ignoreCase = true)) s += 1
        return s
    }

    /** A team matches if any of its significant (>=4 char) tokens appears. */
    private fun matchesTeam(haystack: String, teamTokens: List<String>): Boolean =
        teamTokens.isNotEmpty() && teamTokens.any { haystack.contains(it) }

    private fun tokens(name: String): List<String> =
        normalize(name).split(" ").filter { it.length >= 4 }

    /** Lowercase, strip punctuation/separators (hyphens, &, dots) to spaces. */
    private fun normalize(s: String): String =
        s.lowercase().replace(Regex("[^a-z0-9 ]"), " ").replace(Regex("\\s+"), " ").trim()

    private fun sportCategory(sport: Sport): String = when (sport) {
        Sport.SOCCER -> "football"
        Sport.CRICKET -> "cricket"
    }

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
