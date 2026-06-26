package com.example.matcha.data.streaming

import com.example.matcha.data.Match
import com.example.matcha.data.MatchState
import com.example.matcha.data.MatchTeam
import com.example.matcha.data.Sport
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class IptvResolverTest {

    private val now = 1_000_000_000_000L

    private fun match(
        home: String,
        away: String,
        broadcast: String? = null,
        state: MatchState = MatchState.LIVE,
        kickoff: Long = now,
    ) = Match(
        id = "x", leagueId = "EPL", leagueName = "Premier League", sport = Sport.SOCCER,
        kickoffEpochMs = kickoff,
        home = MatchTeam(home, home, home.take(3), null, null, false),
        away = MatchTeam(away, away, away.take(3), null, null, false),
        state = state, statusDetail = "36'", venue = null, broadcast = broadcast,
    )

    private val m3u = """
        #EXTM3U
        #EXTINF:-1 tvg-id="fs1.us" tvg-name="FOX Sports 1",FOX Sports 1 HD
        #EXTVLCOPT:http-user-agent=MatchaTest/1.0
        https://cdn.example.com/fs1.m3u8
        #EXTINF:-1 tvg-id="espn.us",ESPN
        https://cdn.example.com/espn.m3u8
    """.trimIndent()

    private val epg = """
        <tv>
          <channel id="espn.us"><display-name>ESPN</display-name></channel>
          <programme start="20010909014640 +0000" stop="20010909044640 +0000" channel="espn.us">
            <title>Premier League: Arsenal vs Chelsea</title>
            <desc>Live football coverage.</desc>
          </programme>
        </tv>
    """.trimIndent()

    private fun resolver(m3uText: String? = m3u, epgText: String? = epg) =
        IptvResolver(
            fetch = { url -> if (url.contains("epg")) epgText else m3uText },
            nowMs = { now },
        )

    @Test fun `resolves by broadcast hint via alias`() = runTest {
        // broadcast "FS1" should alias-match the "FOX Sports 1" channel.
        val options = resolver().resolve(match("Arsenal", "Chelsea", broadcast = "FS1"), "https://host/playlist.m3u8", null)
        assertEquals(1, options.size)
        assertEquals("https://cdn.example.com/fs1.m3u8", options.first().url)
        assertEquals("MatchaTest/1.0", options.first().headers["User-Agent"])
    }

    @Test fun `resolves by epg programme when no broadcast hint`() = runTest {
        val options = resolver().resolve(
            match("Arsenal", "Chelsea"),
            "https://host/playlist.m3u8",
            "https://host/epg.xml",
        )
        assertTrue(options.any { it.url == "https://cdn.example.com/espn.m3u8" })
        assertTrue(options.first().label.contains("Arsenal vs Chelsea"))
    }

    @Test fun `returns empty when m3u url blank`() = runTest {
        assertTrue(resolver().resolve(match("Arsenal", "Chelsea", broadcast = "FS1"), "", null).isEmpty())
    }

    @Test fun `returns empty for finished match`() = runTest {
        val options = resolver().resolve(
            match("Arsenal", "Chelsea", broadcast = "FS1", state = MatchState.FINAL),
            "https://host/playlist.m3u8", null,
        )
        assertTrue(options.isEmpty())
    }

    @Test fun `returns empty when playlist has no channels`() = runTest {
        val options = resolver(m3uText = "#EXTM3U").resolve(
            match("Arsenal", "Chelsea", broadcast = "FS1"), "https://host/playlist.m3u8", null,
        )
        assertTrue(options.isEmpty())
    }
}
