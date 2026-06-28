package com.example.matcha.data.streaming

import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone

/**
 * Parses an XMLTV EPG document into [EpgData]. Regex-based (like the macOS
 * port) rather than a full DOM parse: EPG feeds are large and we only need
 * channel display-names and programme title/desc/start/stop. Pure and
 * synchronous for unit testing.
 */
object XmltvParser {

    private val CHANNEL = Regex("""<channel[^>]*id="([^"]+)"[^>]*>(.*?)</channel>""", setOf(RegexOption.DOT_MATCHES_ALL, RegexOption.IGNORE_CASE))
    private val DISPLAY = Regex("""<display-name[^>]*>(.*?)</display-name>""", setOf(RegexOption.DOT_MATCHES_ALL, RegexOption.IGNORE_CASE))
    private val PROGRAMME = Regex("""<programme\s+([^>]+)>(.*?)</programme>""", setOf(RegexOption.DOT_MATCHES_ALL, RegexOption.IGNORE_CASE))
    private val TITLE = Regex("""<title[^>]*>(.*?)</title>""", setOf(RegexOption.DOT_MATCHES_ALL, RegexOption.IGNORE_CASE))
    private val DESC = Regex("""<desc[^>]*>(.*?)</desc>""", setOf(RegexOption.DOT_MATCHES_ALL, RegexOption.IGNORE_CASE))

    fun parse(text: String): EpgData {
        val channelNamesById = LinkedHashMap<String, List<String>>()
        for (m in CHANNEL.findAll(text)) {
            val id = IptvText.normalize(m.groupValues[1])
            val body = m.groupValues[2]
            val names = DISPLAY.findAll(body)
                .map { IptvText.normalize(stripHtml(it.groupValues[1])) }
                .filter { it.isNotEmpty() }
                .toSet()
                .toList()
            channelNamesById[id] = names
        }

        val programs = mutableListOf<EpgProgram>()
        for (m in PROGRAMME.findAll(text)) {
            val attrs = m.groupValues[1]
            val body = m.groupValues[2]
            val startRaw = IptvText.captureQuotedAttribute("start", attrs) ?: continue
            val stopRaw = IptvText.captureQuotedAttribute("stop", attrs) ?: continue
            val start = parseXmltvDate(startRaw) ?: continue
            val end = parseXmltvDate(stopRaw) ?: continue

            val title = TITLE.find(body)?.groupValues?.get(1)?.let { stripHtml(it).trim() }.orEmpty()
            if (title.isEmpty()) continue
            val desc = DESC.find(body)?.groupValues?.get(1)?.let { stripHtml(it).trim() }?.ifEmpty { null }

            val rawChannelId = IptvText.captureQuotedAttribute("channel", attrs)
            val channelId = rawChannelId?.let(IptvText::normalize)
            val channelNames = channelId?.let { channelNamesById[it] } ?: emptyList()

            programs.add(
                EpgProgram(
                    channelId = rawChannelId,
                    normalizedChannelId = channelId,
                    channelNames = channelNames,
                    normalizedChannelNames = channelNames.map(IptvText::normalize),
                    title = title,
                    description = desc,
                    startMs = start,
                    endMs = end,
                ),
            )
        }
        return EpgData(programs, channelNamesById)
    }

    /** XMLTV timestamps: "yyyyMMddHHmmss Z" or bare "yyyyMMddHHmmss" (UTC). */
    internal fun parseXmltvDate(raw: String): Long? {
        val cleaned = raw.trim()
        val withZone = when {
            cleaned.length >= 19 && cleaned[14] == ' ' -> cleaned
            cleaned.length >= 18 -> cleaned.take(14) + " " + cleaned.drop(14)
            else -> cleaned
        }
        SimpleDateFormat("yyyyMMddHHmmss Z", Locale.US).runCatching { parse(withZone) }
            .getOrNull()?.let { return it.time }

        return SimpleDateFormat("yyyyMMddHHmmss", Locale.US)
            .apply { timeZone = TimeZone.getTimeZone("UTC") }
            .runCatching { parse(cleaned.take(14)) }
            .getOrNull()?.time
    }

    private fun stripHtml(input: String): String =
        input
            .replace(Regex("<[^>]+>"), " ")
            .replace("&amp;", "&")
            .replace("&#39;", "'")
            .replace("&quot;", "\"")
            .replace(Regex("\\s+"), " ")
            .trim()
}
