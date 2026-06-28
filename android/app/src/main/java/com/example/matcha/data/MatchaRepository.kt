package com.example.matcha.data

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext

/**
 * Single source of truth for scores. Fetches the favorited leagues from ESPN
 * in parallel, applies the favorite-team filter, and exposes grouped results.
 */
class MatchaRepository(
    private val favorites: FavoritesStore,
    private val api: EspnApi = EspnApi(),
) {
    private val _leagueMatches = MutableStateFlow<List<LeagueMatches>>(emptyList())
    val leagueMatches: StateFlow<List<LeagueMatches>> get() = _leagueMatches.asStateFlow()

    /**
     * Fetch all favorited leagues. If [teamFilter] is non-empty, only matches
     * involving a favorited team are kept; otherwise the whole league shows.
     */
    suspend fun refresh(favoriteLeagueIds: Set<String>, teamFilter: Set<String>) {
        val leagues = favoriteLeagueIds.mapNotNull { Leagues.byId(it) }
        val terms = teamFilter.map { it.lowercase() }

        val results = coroutineScope {
            leagues.map { league ->
                async(Dispatchers.IO) {
                    val matches = api.fetchLeague(league)
                        .filter { match -> terms.isEmpty() || match.matchesAnyTeam(terms) }
                        .sortedWith(compareBy({ it.state.sortOrder }, { it.kickoffEpochMs }))
                    LeagueMatches(league, matches)
                }
            }.awaitAll()
        }

        _leagueMatches.value = results
            .filter { it.matches.isNotEmpty() }
            .sortedBy { it.league.displayName }
    }

    /** One-shot fetch for widgets/workers without retaining state. */
    suspend fun fetchOnce(favoriteLeagueIds: Set<String>, teamFilter: Set<String>): List<Match> =
        withContext(Dispatchers.IO) {
            val leagues = favoriteLeagueIds.mapNotNull { Leagues.byId(it) }
            val terms = teamFilter.map { it.lowercase() }
            coroutineScope {
                leagues.map { league -> async { api.fetchLeague(league) } }.awaitAll()
            }.flatten()
                .filter { terms.isEmpty() || it.matchesAnyTeam(terms) }
                .sortedWith(compareBy({ it.state.sortOrder }, { it.kickoffEpochMs }))
        }

    companion object {
        @Volatile private var instance: MatchaRepository? = null

        fun get(context: Context): MatchaRepository =
            instance ?: synchronized(this) {
                instance ?: MatchaRepository(FavoritesStore(context.applicationContext))
                    .also { instance = it }
            }
    }
}

private val MatchState.sortOrder: Int
    get() = when (this) {
        MatchState.LIVE -> 0
        MatchState.UPCOMING -> 1
        MatchState.FINAL -> 2
    }

private fun Match.matchesAnyTeam(terms: List<String>): Boolean {
    val haystack = listOf(home.name, away.name, home.abbreviation, away.abbreviation)
        .joinToString(" ").lowercase()
    return terms.any { haystack.contains(it) }
}
