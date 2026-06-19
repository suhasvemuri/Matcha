package com.example.matcha.data.streaming

import com.example.matcha.data.Match
import com.example.matcha.data.MatchState
import com.example.matcha.data.MatchTeam
import com.example.matcha.data.Sport
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class StreamedResolverTest {

    private fun match(home: String, away: String, sport: Sport = Sport.SOCCER) = Match(
        id = "x", leagueId = "FFWC", leagueName = "FIFA World Cup", sport = sport,
        kickoffEpochMs = 0,
        home = MatchTeam(home, home, home.take(3), null, null, false),
        away = MatchTeam(away, away, away.take(3), null, null, false),
        state = MatchState.LIVE, statusDetail = "36'", venue = null,
    )

    private fun candidate(title: String, home: String?, away: String?, category: String = "football") =
        StreamedMatch(
            id = title, title = title, category = category,
            teams = StreamedTeams(home?.let { StreamedSide(it) }, away?.let { StreamedSide(it) }),
            sources = emptyList(),
        )

    @Test
    fun matchesExactTeams() {
        val r = StreamedResolver()
        val found = r.bestMatch(
            listOf(candidate("Mexico vs South Korea", "Mexico", "South Korea")),
            match("Mexico", "South Korea"),
        )
        assertEquals("Mexico vs South Korea", found?.title)
    }

    @Test
    fun matchesAcrossNameSeparators() {
        // ESPN "Bosnia-Herzegovina" vs streamed "Bosnia & Herzegovina".
        val r = StreamedResolver()
        val found = r.bestMatch(
            listOf(candidate("Switzerland vs Bosnia & Herzegovina", "Switzerland", "Bosnia & Herzegovina")),
            match("Switzerland", "Bosnia-Herzegovina"),
        )
        assertEquals("Switzerland vs Bosnia & Herzegovina", found?.title)
    }

    @Test
    fun picksBestAmongMany() {
        val r = StreamedResolver()
        val found = r.bestMatch(
            listOf(
                candidate("Some Other Match", "Brazil", "Haiti"),
                candidate("Germany vs Ivory Coast", "Germany", "Ivory Coast"),
            ),
            match("Germany", "Ivory Coast"),
        )
        assertEquals("Germany vs Ivory Coast", found?.title)
    }

    @Test
    fun returnsNullWhenNoTeamMatches() {
        val r = StreamedResolver()
        val found = r.bestMatch(
            listOf(candidate("Cardinals vs Royals", "Cardinals", "Royals", "baseball")),
            match("Mexico", "South Korea"),
        )
        assertNull(found)
    }
}
