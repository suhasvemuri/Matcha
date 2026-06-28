package com.example.matcha.data.streaming

import com.example.matcha.data.Match
import com.example.matcha.data.MatchState
import com.example.matcha.data.Sport
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.net.HttpURLConnection
import java.net.URL

/**
 * Android port of the macOS IPTVResolver. Given a user-configured M3U playlist
 * (and optional XMLTV EPG), finds channels that carry a [Match] — first by the
 * broadcast network hint, then by matching the EPG's now/next programme to the
 * teams. Returns [StreamOption]s whose direct stream URLs play natively in
 * ExoPlayer (no CORS/token wall), carrying any per-channel request headers.
 *
 * Pure matching logic is separated from network fetching: pass a custom
 * [fetch]/[nowMs] in tests; production uses [httpGet] + the wall clock.
 */
class IptvResolver(
    private val fetch: suspend (url: String) -> String? = { httpGet(it) },
    private val nowMs: () -> Long = System::currentTimeMillis,
) {
    private var cachedM3uUrl = ""
    private var lastLoadedAt = 0L
    private var channels: List<IptvChannel> = emptyList()
    private var channelMap: Map<String, IptvChannel> = emptyMap()

    private var cachedEpgUrl = ""
    private var lastEpgAt = 0L
    private var programs: List<EpgProgram> = emptyList()

    suspend fun resolve(
        match: Match,
        m3uUrl: String,
        epgUrl: String?,
        limit: Int = 6,
    ): List<StreamOption> = withContext(Dispatchers.IO) {
        if (m3uUrl.isBlank()) return@withContext emptyList()
        if (match.state != MatchState.LIVE && match.state != MatchState.UPCOMING) return@withContext emptyList()

        if (m3uUrl != cachedM3uUrl || nowMs() - lastLoadedAt > M3U_TTL_MS) {
            fetch(m3uUrl)?.let { text ->
                channels = M3uParser.parse(text)
                channelMap = M3uParser.channelMap(channels)
                cachedM3uUrl = m3uUrl
                lastLoadedAt = nowMs()
            }
        }
        if (channels.isEmpty()) return@withContext emptyList()

        val ranked = mutableListOf<StreamOption>()
        ranked += directMatches(match, limit)

        if (ranked.size < limit && !epgUrl.isNullOrBlank()) {
            if (epgUrl != cachedEpgUrl || nowMs() - lastEpgAt > EPG_TTL_MS) {
                fetch(epgUrl)?.let { text ->
                    programs = XmltvParser.parse(text).programs
                    cachedEpgUrl = epgUrl
                    lastEpgAt = nowMs()
                }
            }
            if (programs.isNotEmpty()) ranked += bestEpgMatches(match, limit)
        }

        dedupe(ranked, limit)
    }

    // --- broadcast-hint matching -------------------------------------------

    private fun directMatches(match: Match, limit: Int): List<StreamOption> {
        val hints = broadcastHints(match)
        if (hints.isEmpty()) return emptyList()
        val out = mutableListOf<StreamOption>()
        for (hint in hints) {
            if (IptvText.normalize(hint).isEmpty()) continue
            val channel = findChannel(hint) ?: continue
            out += channel.toOption(channelName = hint, programTitle = null)
            if (out.size >= limit) break
        }
        return dedupe(out, limit)
    }

    /** Exact alias hit first, then substring-fuzzy against the channel index. */
    private fun findChannel(name: String): IptvChannel? {
        val normalized = IptvText.normalize(name)
        for (candidate in IptvText.aliasCandidates(normalized)) {
            channelMap[candidate]?.let { return it }
        }
        for (candidate in IptvText.aliasCandidates(normalized)) {
            channelMap.entries.firstOrNull { (key, _) ->
                key.contains(candidate) || candidate.contains(key)
            }?.let { return it.value }
        }
        return null
    }

    // --- EPG matching ------------------------------------------------------

    private fun bestEpgMatches(match: Match, limit: Int): List<StreamOption> {
        val now = nowMs()
        val isLive = match.state == MatchState.LIVE
        val start = if (match.kickoffEpochMs > 0) match.kickoffEpochMs else now
        val windowStart = if (isLive) now - 120 * MIN else start - 8 * HOUR
        val windowEnd = if (isLive) now + 45 * MIN else start + 14 * HOUR

        val homeTokens = tokenize(match.home.name)
        val awayTokens = tokenize(match.away.name)
        val leagueTokens = tokenize(match.leagueName)
        val league = IptvText.normalize(match.leagueName)
        val sport = sportKey(match.sport)
        val hints = broadcastHints(match).map(IptvText::normalize)

        data class Ranked(val program: EpgProgram, val channel: IptvChannel, val score: Double)
        val ranked = mutableListOf<Ranked>()

        for (program in programs) {
            if (program.endMs < windowStart || program.startMs > windowEnd) continue
            val channel = channelForProgram(program) ?: continue
            if (!isLikelySportsChannel(channel, program)) continue

            val titleTokens = IptvText.normalize(program.title).split(' ').filter { it.isNotEmpty() }.toSet()
            val descTokens = IptvText.normalize(program.description ?: "").split(' ').filter { it.isNotEmpty() }.toSet()

            val homeHits = titleTokens.intersect(homeTokens).size + 0.5 * descTokens.intersect(homeTokens).size
            val awayHits = titleTokens.intersect(awayTokens).size + 0.5 * descTokens.intersect(awayTokens).size
            val leagueHits = titleTokens.intersect(leagueTokens).size + 0.4 * descTokens.intersect(leagueTokens).size

            var score = 0.0
            if (homeHits > 0) score += minOf(3.0, homeHits)
            if (awayHits > 0) score += minOf(3.0, awayHits)
            if (homeHits > 0 && awayHits > 0) score += 2.0
            if (leagueHits > 0) score += minOf(2.5, leagueHits)
            val title = IptvText.normalize(program.title)
            val desc = IptvText.normalize(program.description ?: "")
            if (league.contains("world cup") && (titleTokens.contains("wc") || descTokens.contains("wc"))) score += 1.2
            if (sport == "cricket" && (title.contains("cricket") || desc.contains("cricket"))) score += 0.9
            if (sport == "soccer" && (title.contains("soccer") || title.contains("football") || desc.contains("soccer") || desc.contains("football"))) score += 0.8
            if (hints.any { h -> h.isNotEmpty() && channel.normalizedNames.any { it.contains(h) || h.contains(it) } }) score += 2.5

            val delta = kotlin.math.abs(program.startMs - start)
            if (delta <= 30 * MIN) score += 1.5 else if (delta <= 90 * MIN) score += 0.8

            if (score < 1.8) continue
            ranked += Ranked(program, channel, score)
        }

        return ranked
            .sortedWith(compareByDescending<Ranked> { it.score }.thenBy { it.program.startMs })
            .map { it.channel.toOption(
                channelName = it.channel.names.firstOrNull() ?: it.program.channelNames.firstOrNull() ?: "Sports Channel",
                programTitle = it.program.title,
            ) }
            .let { dedupe(it, limit) }
    }

    private fun channelForProgram(program: EpgProgram): IptvChannel? {
        program.normalizedChannelId?.let { id ->
            channels.firstOrNull { it.normalizedTvgId == id }?.let { return it }
        }
        for (name in program.normalizedChannelNames) {
            channels.firstOrNull { it.normalizedNames.contains(name) }?.let { return it }
            channels.firstOrNull { ch -> ch.normalizedNames.any { it.contains(name) || name.contains(it) } }?.let { return it }
        }
        return null
    }

    private fun isLikelySportsChannel(channel: IptvChannel, program: EpgProgram): Boolean {
        val hay = (channel.names.joinToString(" ") + " " + (channel.groupTitle ?: "") + " " +
            program.title + " " + (program.description ?: "")).lowercase()
        return SPORTS_TERMS.any { hay.contains(it) }
    }

    // --- helpers -----------------------------------------------------------

    private fun IptvChannel.toOption(channelName: String, programTitle: String?): StreamOption {
        val hd = normalizedNames.any { it.contains("hd") || it.contains("4k") || it.contains("fhd") }
        val label = buildString {
            append(channelName)
            if (hd) append(" · HD")
            programTitle?.takeIf { it.isNotBlank() }?.let { append(" — $it") }
        }
        return StreamOption(label = label, url = streamUrl, source = "iptv", isHd = hd, language = null, headers = headers)
    }

    private fun broadcastHints(match: Match): List<String> =
        match.broadcast?.split('/', ',', '&', '|')?.map { it.trim() }?.filter { it.isNotEmpty() } ?: emptyList()

    private fun tokenize(name: String): Set<String> =
        IptvText.normalize(name).split(' ').filter { it.length > 2 }.toSet()

    private fun sportKey(sport: Sport): String = when (sport) {
        Sport.SOCCER -> "soccer"
        Sport.CRICKET -> "cricket"
        Sport.F1 -> "motorsports"
    }

    private fun dedupe(options: List<StreamOption>, limit: Int): List<StreamOption> {
        val seen = HashSet<String>()
        val out = mutableListOf<StreamOption>()
        for (o in options) {
            val key = o.url + "|" + IptvText.normalize(o.label)
            if (!seen.add(key)) continue
            out += o
            if (out.size >= limit) break
        }
        return out
    }

    companion object {
        private const val MIN = 60_000L
        private const val HOUR = 3_600_000L
        private const val M3U_TTL_MS = 15 * 60_000L
        private const val EPG_TTL_MS = 10 * 60_000L

        private val SPORTS_TERMS = listOf(
            "sport", "espn", "star sports", "sky sports", "tnt", "fox sports", "bein", "sonysports",
            "sony sports", "supersport", "willow", "astro", "ten sports", "premier sports",
        )

        private fun httpGet(urlString: String): String? {
            var conn: HttpURLConnection? = null
            return try {
                conn = (URL(urlString).openConnection() as HttpURLConnection).apply {
                    requestMethod = "GET"
                    connectTimeout = 12_000
                    readTimeout = 12_000
                    setRequestProperty("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
                }
                if (conn.responseCode in 200..299) conn.inputStream.bufferedReader().use { it.readText() } else null
            } catch (_: Exception) {
                null
            } finally {
                conn?.disconnect()
            }
        }
    }
}
