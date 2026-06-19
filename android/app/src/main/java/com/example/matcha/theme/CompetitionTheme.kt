package com.example.matcha.theme

import androidx.compose.ui.graphics.Color

/**
 * Apple Sports themes the whole canvas by competition. Each followed league
 * gets an accent + a canvas gradient; the feed themes itself by the dominant
 * competition on screen, and the brand green is the default.
 */
data class CompetitionTheme(
    val accent: Color,
    val gradientTop: Color,
    val gradientBottom: Color = Color(0xFF05070A),
)

object CompetitionThemes {
    private val WorldCup = CompetitionTheme(Color(0xFF5B8DEF), Color(0xFF16275C))
    private val Champions = CompetitionTheme(Color(0xFF5AA9FF), Color(0xFF0C1F4D))
    private val Europa = CompetitionTheme(Color(0xFFFF8A3D), Color(0xFF3A1E07))
    private val Premier = CompetitionTheme(Color(0xFFB388FF), Color(0xFF2A0F49))
    private val LaLiga = CompetitionTheme(Color(0xFFFF6B6B), Color(0xFF3A0E12))
    private val Bundesliga = CompetitionTheme(Color(0xFFFF5252), Color(0xFF360A0A))
    private val SerieA = CompetitionTheme(Color(0xFF4FA8E0), Color(0xFF0A2A40))
    private val Cricket = CompetitionTheme(Color(0xFF4FC3F7), Color(0xFF0A2533))
    val Matcha = CompetitionTheme(Color(0xFF6FD66F), Color(0xFF0E3A22))

    fun forLeague(leagueId: String?): CompetitionTheme = when (leagueId) {
        "FFWC", "FFWWC", "FFWCQUEFA", "CONMEBOL", "CONCACAF", "CAF", "AFC", "OFC" -> WorldCup
        "UEFA" -> Champions
        "EUEFA" -> Europa
        "EPL" -> Premier
        "ESP" -> LaLiga
        "GER" -> Bundesliga
        "ITA" -> SerieA
        "IPL", "CWC", "BBL" -> Cricket
        else -> Matcha
    }
}
