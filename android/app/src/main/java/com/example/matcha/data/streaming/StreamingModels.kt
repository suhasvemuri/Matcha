package com.example.matcha.data.streaming

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.intOrNull

/** A resolved, openable stream for a match. */
data class StreamOption(
    val label: String,
    val url: String,
    val source: String,
    val isHd: Boolean,
    val language: String?,
    /** Per-stream request headers (IPTV channels often need User-Agent/Referer). */
    val headers: Map<String, String> = emptyMap(),
)

/** streamed.st match-list element from /api/matches/... (subset). */
@Serializable
data class StreamedMatch(
    @Serializable(with = FlexibleStringSerializer::class) val id: String = "",
    val title: String = "",
    val category: String = "",
    val teams: StreamedTeams? = null,
    val sources: List<StreamedSource> = emptyList(),
)

@Serializable
data class StreamedTeams(
    val home: StreamedSide? = null,
    val away: StreamedSide? = null,
)

@Serializable
data class StreamedSide(val name: String = "")

@Serializable
data class StreamedSource(
    val source: String = "",
    @Serializable(with = FlexibleStringSerializer::class) val id: String = "",
)

/** streamed.st `/api/stream/{source}/{id}` element (subset). */
@Serializable
data class StreamedStream(
    val id: String? = null,
    val streamNo: Int? = null,
    val language: String? = null,
    val hd: Boolean? = null,
    val embedUrl: String? = null,
    val streamUrl: String? = null,
    val url: String? = null,
    val source: String? = null,
) {
    val anyUrl: String? get() = embedUrl ?: streamUrl ?: url
}

/** streamed.st returns `id` as either a string or an int; normalize to String. */
object FlexibleStringSerializer : kotlinx.serialization.KSerializer<String> {
    override val descriptor =
        kotlinx.serialization.descriptors.PrimitiveSerialDescriptor(
            "FlexibleString",
            kotlinx.serialization.descriptors.PrimitiveKind.STRING,
        )

    override fun deserialize(decoder: kotlinx.serialization.encoding.Decoder): String {
        val input = decoder as? kotlinx.serialization.json.JsonDecoder
            ?: return decoder.decodeString()
        return when (val el: JsonElement = input.decodeJsonElement()) {
            is JsonPrimitive -> el.intOrNull?.toString() ?: el.content
            else -> ""
        }
    }

    override fun serialize(encoder: kotlinx.serialization.encoding.Encoder, value: String) {
        encoder.encodeString(value)
    }
}
