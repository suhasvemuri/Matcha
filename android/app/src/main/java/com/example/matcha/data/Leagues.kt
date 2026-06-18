package com.example.matcha.data

/** Sports Matcha can show. Cricket uses a different upstream and is added later. */
enum class Sport(val displayName: String) {
    SOCCER("Football"),
    CRICKET("Cricket"),
}

/**
 * A followable competition. [slug] is the ESPN league path segment used to
 * build the scoreboard URL; [id] is Matcha's stable key (used for favorites
 * and widget config). Mirrors the macOS app's `Scoreboard.Urls` catalog.
 */
data class League(
    val id: String,
    val displayName: String,
    val sport: Sport,
    val espnSport: String,
    val slug: String,
    val country: String? = null,
) {
    /** ESPN scoreboard endpoint for a given inclusive yyyyMMdd date window. */
    fun scoreboardUrl(startYmd: String, endYmd: String): String =
        "https://site.api.espn.com/apis/site/v2/sports/$espnSport/$slug/scoreboard?dates=$startYmd-$endYmd"
}

object Leagues {
    private fun soccer(id: String, name: String, slug: String, country: String? = null) =
        League(id, name, Sport.SOCCER, "soccer", slug, country)

    val all: List<League> = listOf(
        // FIFA World Cup family — what the user specifically wanted surfaced.
        soccer("FFWC", "FIFA World Cup", "fifa.world", "International"),
        soccer("FFWWC", "FIFA Women's World Cup", "fifa.wwc", "International"),
        soccer("FFWCQUEFA", "FIFA WC UEFA Qualifiers", "fifa.worldq.uefa", "Europe"),
        soccer("CONMEBOL", "FIFA WC CONMEBOL Qualifiers", "fifa.worldq.conmebol", "South America"),
        soccer("CONCACAF", "FIFA WC CONCACAF Qualifiers", "fifa.worldq.concacaf", "North America"),
        soccer("CAF", "FIFA WC African Qualifiers", "fifa.worldq.caf", "Africa"),
        soccer("AFC", "FIFA WC Asian Qualifiers", "fifa.worldq.afc", "Asia"),
        soccer("OFC", "FIFA WC Oceanian Qualifiers", "fifa.worldq.ofc", "Oceania"),
        // Club competitions
        soccer("UEFA", "UEFA Champions League", "uefa.champions", "Europe"),
        soccer("EUEFA", "UEFA Europa League", "uefa.europa", "Europe"),
        soccer("EPL", "Premier League", "ENG.1", "England"),
        soccer("ESP", "La Liga", "ESP.1", "Spain"),
        soccer("GER", "Bundesliga", "GER.1", "Germany"),
        soccer("ITA", "Serie A", "ITA.1", "Italy"),
        soccer("FRA", "Ligue 1", "FRA.1", "France"),
        soccer("NED", "Eredivisie", "NED.1", "Netherlands"),
        soccer("POR", "Primeira Liga", "POR.1", "Portugal"),
        soccer("MLS", "MLS", "USA.1", "United States"),
        soccer("NWSL", "NWSL", "USA.NWSL", "United States"),
        soccer("MEX", "Liga MX", "MEX.1", "Mexico"),
    )

    private val byId = all.associateBy { it.id }

    fun byId(id: String): League? = byId[id]

    /** Sensible defaults for a fresh install before the user picks favorites. */
    val defaultFavoriteIds: Set<String> = setOf("FFWC", "EPL", "UEFA")
}
