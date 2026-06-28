package com.example.matcha.ui.main

import com.example.matcha.data.EspnApi
import com.example.matcha.data.Leagues
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.text.SimpleDateFormat
import java.util.Locale

class MatchaDataTest {

    @Test
    fun worldCup_isInCatalog_withCorrectSlug() {
        val wc = Leagues.byId("FFWC")
        assertNotNull(wc)
        assertEquals("fifa.world", wc!!.slug)
        assertEquals("soccer", wc.espnSport)
    }

    @Test
    fun scoreboardUrl_buildsExpectedEspnPath() {
        val url = Leagues.byId("EPL")!!.scoreboardUrl("20260616", "20260624")
        assertTrue(url.contains("/soccer/ENG.1/scoreboard"))
        assertTrue(url.endsWith("dates=20260616-20260624"))
    }

    @Test
    fun dynamicRange_spansEightDays_aroundNow() {
        val fmt = SimpleDateFormat("yyyyMMdd", Locale.US)
        val now = fmt.parse("20260618")!!
        val (start, end) = EspnApi.dynamicRange(now)
        assertEquals("20260615", start)
        assertEquals("20260623", end)
    }

    @Test
    fun defaultFavorites_includeWorldCup() {
        assertTrue(Leagues.defaultFavoriteIds.contains("FFWC"))
    }
}
