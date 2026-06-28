package com.example.matcha.data.streaming

/**
 * Parses an M3U/M3U8 playlist into [IptvChannel]s. Handles the common
 * extensions seen in IPTV playlists: `#EXTINF` attributes (tvg-name/tvg-id/
 * group-title and the trailing display name), `#EXTVLCOPT:` header options,
 * and pipe-suffixed URLs (`url|User-Agent=…&Referer=…`). Pure and synchronous
 * so it's unit-testable; the resolver handles fetching.
 */
object M3uParser {

    fun parse(content: String): List<IptvChannel> {
        val result = mutableListOf<IptvChannel>()
        var pendingNames: List<String> = emptyList()
        var pendingTvgId: String? = null
        var pendingGroupTitle: String? = null
        var pendingHeaders = mutableMapOf<String, String>()

        fun reset() {
            pendingNames = emptyList()
            pendingTvgId = null
            pendingGroupTitle = null
            pendingHeaders = mutableMapOf()
        }

        for (raw in content.lineSequence()) {
            val line = raw.trim()
            if (line.isEmpty()) continue

            if (line.startsWith("#EXTINF")) {
                pendingNames = extractNames(line)
                pendingTvgId = IptvText.captureQuotedAttribute("tvg-id", line)
                pendingGroupTitle = IptvText.captureQuotedAttribute("group-title", line)
                pendingHeaders = mutableMapOf()
                continue
            }

            if (line.lowercase().startsWith("#extvlcopt:")) {
                val payload = line.substring("#EXTVLCOPT:".length)
                val eq = payload.indexOf('=')
                if (eq > 0) {
                    val key = IptvText.canonicalHeaderName(payload.substring(0, eq).trim())
                    val value = payload.substring(eq + 1).trim()
                    if (key != null && value.isNotEmpty()) pendingHeaders[key] = value
                }
                continue
            }

            if (line.startsWith("#")) continue

            val (streamUrl, urlHeaders) = parseStreamUrlAndHeaders(line)
            if (streamUrl == null) { reset(); continue }

            val names = pendingNames.ifEmpty { listOf(line) }
            val normalized = names.map(IptvText::normalize).filter { it.isNotEmpty() }.toSet()
            if (normalized.isNotEmpty()) {
                val merged = LinkedHashMap(pendingHeaders).apply { putAll(urlHeaders) }
                result.add(
                    IptvChannel(
                        names = names,
                        normalizedNames = normalized,
                        tvgId = pendingTvgId,
                        normalizedTvgId = pendingTvgId?.let(IptvText::normalize),
                        groupTitle = pendingGroupTitle,
                        streamUrl = streamUrl,
                        headers = merged,
                    ),
                )
            }
            reset()
        }
        return result
    }

    /** tvg-name + tvg-id + trailing display name (deduped), in EXTINF order. */
    internal fun extractNames(extinf: String): List<String> {
        val names = LinkedHashSet<String>()
        IptvText.captureQuotedAttribute("tvg-name", extinf)?.let { names.add(it) }
        IptvText.captureQuotedAttribute("tvg-id", extinf)?.let { names.add(it) }
        val comma = extinf.indexOf(',')
        if (comma >= 0) {
            val display = extinf.substring(comma + 1).trim()
            if (display.isNotEmpty()) names.add(display)
        }
        return names.toList()
    }

    /**
     * Split `url|Header=Value&Header2=Value2` into the URL and its headers.
     * The header segment is URL-decoded and keys canonicalized; unknown keys
     * are kept as-is so nothing is silently dropped.
     */
    internal fun parseStreamUrlAndHeaders(line: String): Pair<String?, Map<String, String>> {
        val pipe = line.indexOf('|')
        val rawUrl = (if (pipe >= 0) line.substring(0, pipe) else line).trim()
        if (!rawUrl.startsWith("http")) return null to emptyMap()
        if (pipe < 0) return rawUrl to emptyMap()

        val headers = mutableMapOf<String, String>()
        for (pair in line.substring(pipe + 1).split('&')) {
            val eq = pair.indexOf('=')
            if (eq <= 0) continue
            val rawKey = pair.substring(0, eq).trim()
            val key = IptvText.canonicalHeaderName(rawKey) ?: rawKey
            val value = runCatching { java.net.URLDecoder.decode(pair.substring(eq + 1).trim(), "UTF-8") }
                .getOrDefault(pair.substring(eq + 1).trim())
            if (key.isNotEmpty() && value.isNotEmpty()) headers[key] = value
        }
        return rawUrl to headers
    }

    /** Index channels by every normalized name and tvg-id, for O(1) lookup. */
    fun channelMap(channels: List<IptvChannel>): Map<String, IptvChannel> {
        val map = LinkedHashMap<String, IptvChannel>()
        for (channel in channels) {
            channel.normalizedNames.forEach { map[it] = channel }
            channel.normalizedTvgId?.takeIf { it.isNotEmpty() }?.let { map[it] = channel }
        }
        return map
    }
}
