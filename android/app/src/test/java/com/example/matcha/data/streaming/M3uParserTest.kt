package com.example.matcha.data.streaming

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class M3uParserTest {

    @Test fun `parses extinf attributes and trailing name`() {
        val m3u = """
            #EXTM3U
            #EXTINF:-1 tvg-id="fs1.us" tvg-name="FOX Sports 1" group-title="USA Sports",FOX Sports 1 HD
            https://cdn.example.com/fs1/index.m3u8
        """.trimIndent()

        val channels = M3uParser.parse(m3u)
        assertEquals(1, channels.size)
        val c = channels.first()
        assertEquals("https://cdn.example.com/fs1/index.m3u8", c.streamUrl)
        assertEquals("fs1.us", c.tvgId)
        assertEquals("USA Sports", c.groupTitle)
        // tvg-name, tvg-id and display name are all retained as names.
        assertTrue(c.names.contains("FOX Sports 1"))
        assertTrue(c.names.contains("FOX Sports 1 HD"))
        assertTrue(c.normalizedNames.contains("fox sports 1"))
    }

    @Test fun `parses EXTVLCOPT headers`() {
        val m3u = """
            #EXTINF:-1,Sky Sports Main Event
            #EXTVLCOPT:http-user-agent=MyPlayer/1.0
            #EXTVLCOPT:http-referrer=https://ref.example.com/
            https://cdn.example.com/sky/index.m3u8
        """.trimIndent()

        val c = M3uParser.parse(m3u).single()
        assertEquals("MyPlayer/1.0", c.headers["User-Agent"])
        assertEquals("https://ref.example.com/", c.headers["Referer"])
    }

    @Test fun `parses pipe-suffixed url headers and decodes values`() {
        val line = "https://cdn.example.com/live.ts|User-Agent=VLC&Referer=https%3A%2F%2Fsite.tv%2F"
        val (url, headers) = M3uParser.parseStreamUrlAndHeaders(line)
        assertEquals("https://cdn.example.com/live.ts", url)
        assertEquals("VLC", headers["User-Agent"])
        assertEquals("https://site.tv/", headers["Referer"])
    }

    @Test fun `rejects non-http url`() {
        val (url, _) = M3uParser.parseStreamUrlAndHeaders("plugin://something")
        assertNull(url)
    }

    @Test fun `channelMap indexes by name and tvg id`() {
        val m3u = """
            #EXTINF:-1 tvg-id="espn",ESPN
            https://cdn.example.com/espn.m3u8
        """.trimIndent()
        val map = M3uParser.channelMap(M3uParser.parse(m3u))
        assertTrue(map.containsKey("espn"))
    }

    @Test fun `skips entries without a usable url`() {
        val m3u = """
            #EXTINF:-1,Broken Channel
            #EXTINF:-1,Good Channel
            https://cdn.example.com/good.m3u8
        """.trimIndent()
        // First EXTINF has no URL line before the next EXTINF; only the good one survives.
        val channels = M3uParser.parse(m3u)
        assertEquals(1, channels.size)
        assertEquals("https://cdn.example.com/good.m3u8", channels.first().streamUrl)
    }
}
