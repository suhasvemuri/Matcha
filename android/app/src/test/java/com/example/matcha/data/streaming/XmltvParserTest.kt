package com.example.matcha.data.streaming

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone

class XmltvParserTest {

    private val sample = """
        <?xml version="1.0"?>
        <tv>
          <channel id="espn.us"><display-name>ESPN</display-name></channel>
          <programme start="20260624183000 +0000" stop="20260624203000 +0000" channel="espn.us">
            <title>Premier League: Arsenal vs Chelsea</title>
            <desc>Live football from the Emirates.</desc>
          </programme>
        </tv>
    """.trimIndent()

    @Test fun `parses channel names by id`() {
        val data = XmltvParser.parse(sample)
        assertEquals(listOf("espn"), data.channelNamesById["espn us"])
    }

    @Test fun `parses programme title desc and channel link`() {
        val data = XmltvParser.parse(sample)
        val p = data.programs.single()
        assertEquals("Premier League: Arsenal vs Chelsea", p.title)
        assertTrue(p.description!!.contains("football"))
        assertEquals("espn us", p.normalizedChannelId)
        assertTrue(p.normalizedChannelNames.contains("espn"))
    }

    @Test fun `parses xmltv date with timezone offset`() {
        val expected = SimpleDateFormat("yyyyMMddHHmmss", Locale.US)
            .apply { timeZone = TimeZone.getTimeZone("UTC") }
            .parse("20260624183000")!!.time
        assertEquals(expected, XmltvParser.parseXmltvDate("20260624183000 +0000"))
    }

    @Test fun `bare xmltv date is treated as utc`() {
        val withZone = XmltvParser.parseXmltvDate("20260624183000 +0000")
        val bare = XmltvParser.parseXmltvDate("20260624183000")
        assertNotNull(bare)
        assertEquals(withZone, bare)
    }
}
