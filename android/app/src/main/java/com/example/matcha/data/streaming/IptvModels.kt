package com.example.matcha.data.streaming

/**
 * A single IPTV channel parsed from an M3U playlist: its display names, the
 * stream URL, and any per-channel request headers (User-Agent/Referer/…)
 * needed to actually open the stream.
 */
data class IptvChannel(
    val names: List<String>,
    val normalizedNames: Set<String>,
    val tvgId: String?,
    val normalizedTvgId: String?,
    val groupTitle: String?,
    val streamUrl: String,
    val headers: Map<String, String>,
)

/** A single EPG programme (what airs on a channel between [startMs] and [endMs]). */
data class EpgProgram(
    val channelId: String?,
    val normalizedChannelId: String?,
    val channelNames: List<String>,
    val normalizedChannelNames: List<String>,
    val title: String,
    val description: String?,
    val startMs: Long,
    val endMs: Long,
)

/** Parsed XMLTV: programmes plus a channel-id → display-names index. */
data class EpgData(
    val programs: List<EpgProgram>,
    val channelNamesById: Map<String, List<String>>,
)

/**
 * Text helpers shared by the M3U/XMLTV parsers and the resolver. Ported from
 * the macOS IPTVResolver so channel/program matching behaves identically.
 */
internal object IptvText {

    /** Lowercase, fold every non-alphanumeric run to a single space, trim. */
    fun normalize(input: String): String =
        input.lowercase()
            .map { if (it.isLetterOrDigit()) it else ' ' }
            .joinToString("")
            .split(' ')
            .filter { it.isNotEmpty() }
            .joinToString(" ")

    /** Canonical HTTP header name for an M3U option key, or null if unsupported. */
    fun canonicalHeaderName(raw: String): String? = when (raw.trim().lowercase()) {
        "user-agent", "http-user-agent", "ua" -> "User-Agent"
        "referer", "referrer", "http-referrer", "http-referer" -> "Referer"
        "origin" -> "Origin"
        "cookie" -> "Cookie"
        "authorization" -> "Authorization"
        else -> null
    }

    /** Pull the value of `key="..."` out of an EXTINF / programme attribute line. */
    fun captureQuotedAttribute(key: String, line: String): String? =
        Regex("$key=\"([^\"]+)\"").find(line)?.groupValues?.get(1)

    /**
     * Broaden a normalized channel name into alias candidates: the raw name,
     * a quality-suffix-stripped form ("hd"/"4k"/"us"…), and known short aliases
     * ("fox sports 1" → "fs1"). Mirrors the macOS alias table.
     */
    fun aliasCandidates(normalized: String): List<String> {
        if (normalized.isEmpty()) return emptyList()
        val candidates = LinkedHashSet<String>()
        candidates.add(normalized)

        val stripped = normalized
            .replace(" usa", "")
            .replace(" us", "")
            .replace(" hd", "")
            .replace(" 4k", "")
            .replace(" fhd", "")
            .trim()
        if (stripped.isNotEmpty()) candidates.add(stripped)

        for ((key, values) in ALIASES) {
            if (stripped.contains(key) || key.contains(stripped)) candidates.addAll(values)
        }
        return candidates.toList()
    }

    private val ALIASES: Map<String, List<String>> = mapOf(
        "nbc sports" to listOf("nbcsn"),
        "tnt sports" to listOf("tnt"),
        "fox sports 1" to listOf("fs1"),
        "fox sports 2" to listOf("fs2"),
        "espn deportes" to listOf("espn dep"),
        "bein sports" to listOf("bein", "be in sports"),
        "sky sports" to listOf("skysp", "sky"),
        "peacock" to listOf("peacock tv"),
    )
}
