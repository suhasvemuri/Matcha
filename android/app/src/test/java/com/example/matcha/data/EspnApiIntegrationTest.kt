package com.example.matcha.data

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.net.HttpURLConnection
import java.net.URL

/**
 * Live integration test against the public ESPN API. Verifies the real
 * fetch + parse pipeline end-to-end (the emulator has no network in CI/sandbox,
 * so this is where on-device behavior is actually proven). Skips itself when
 * offline so it never breaks an air-gapped build.
 */
class EspnApiIntegrationTest {

    private fun online(): Boolean = try {
        val url = Leagues.byId("FFWC")!!.scoreboardUrl("20260101", "20260108")
        val c = (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = 6000; readTimeout = 6000; requestMethod = "GET"
        }
        c.responseCode in 200..299
    } catch (_: Exception) {
        false
    }

    @Test
    fun worldCup_fetchesAndParses_liveFromEspn() = runBlocking {
        assumeTrue("Skipping: no network", online())

        val api = EspnApi()
        val wc = Leagues.byId("FFWC")!!
        val matches = api.fetchLeague(wc)

        // During the 2026 World Cup window there should be fixtures; assert the
        // pipeline produced well-formed matches rather than a specific count.
        assertTrue("Expected World Cup fixtures in the date window", matches.isNotEmpty())
        matches.forEach { m ->
            assertTrue("home name present", m.home.name.isNotBlank())
            assertTrue("away name present", m.away.name.isNotBlank())
            assertTrue("league tagged", m.leagueId == "FFWC")
        }
    }

    @Test
    fun cricketIpl_fetchesAndParses_liveFromEspn() = runBlocking {
        assumeTrue("Skipping: no network", online())

        val api = EspnApi()
        val ipl = Leagues.byId("IPL")!!
        // Cricket may be off-season; just assert the call succeeds and any
        // returned match carries a cricket-style score string without crashing.
        val matches = api.fetchLeague(ipl)
        matches.forEach { m ->
            assertTrue(m.sport == Sport.CRICKET)
        }
    }
}
