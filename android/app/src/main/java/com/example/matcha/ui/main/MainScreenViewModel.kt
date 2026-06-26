package com.example.matcha.ui.main

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.example.matcha.data.FavoritesStore
import com.example.matcha.data.LeagueMatches
import com.example.matcha.data.Match
import com.example.matcha.data.MatchState
import com.example.matcha.data.MatchaRepository
import com.example.matcha.data.SettingsStore
import com.example.matcha.data.streaming.IptvResolver
import com.example.matcha.data.streaming.StreamOption
import com.example.matcha.data.streaming.StreamedResolver
import com.example.matcha.notifications.LiveScoreService
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

class MainScreenViewModel(app: Application) : AndroidViewModel(app) {

    private val favorites = FavoritesStore(app)
    private val repository = MatchaRepository.get(app)
    private val resolver = StreamedResolver()
    private val iptvResolver = IptvResolver()
    private val settingsStore = SettingsStore(app)

    private val _isRefreshing = MutableStateFlow(false)
    val isRefreshing: StateFlow<Boolean> = _isRefreshing.asStateFlow()

    private val _streamSheet = MutableStateFlow<StreamSheetState?>(null)
    val streamSheet: StateFlow<StreamSheetState?> = _streamSheet.asStateFlow()

    /** Lowercased favorite team terms, for the "My Teams" star indicator. */
    val favoriteTeams: StateFlow<Set<String>> =
        favorites.favoriteTeamNames
            .map { names -> names.map { it.lowercase() }.toSet() }
            .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptySet())

    /** Favorite league ids (e.g. for the F1 races section). */
    val favoriteLeagues: StateFlow<Set<String>> =
        favorites.favoriteLeagueIds
            .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptySet())

    /** Combined favorites snapshot, re-fetched whenever the user changes them. */
    private val favoriteSnapshot: StateFlow<FavoriteSnapshot> =
        combine(favorites.favoriteLeagueIds, favorites.favoriteTeamNames) { leagues, teams ->
            FavoriteSnapshot(leagues, teams)
        }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), FavoriteSnapshot())

    val uiState: StateFlow<ScoresUiState> =
        repository.leagueMatches
            .combine(_isRefreshing) { groups, refreshing ->
                when {
                    groups.isEmpty() && refreshing -> ScoresUiState.Loading
                    groups.isEmpty() -> ScoresUiState.Empty
                    else -> ScoresUiState.Success(groups)
                }
            }
            .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), ScoresUiState.Loading)

    init {
        // Refresh on launch and whenever favorites change.
        viewModelScope.launch {
            favoriteSnapshot.collect { refresh() }
        }
    }

    fun refresh() {
        viewModelScope.launch {
            _isRefreshing.value = true
            val snap = favoriteSnapshot.first()
            runCatching { repository.refresh(snap.leagues, snap.teams) }
            _isRefreshing.value = false
            startLiveTrackingIfNeeded()
        }
    }

    /** Quietly re-fetch (no spinner) when a live match is on — for auto-refresh. */
    fun refreshIfLive() {
        val hasLive = repository.leagueMatches.value
            .any { group -> group.matches.any { it.state == MatchState.LIVE } }
        if (!hasLive) return
        viewModelScope.launch {
            val snap = favoriteSnapshot.first()
            runCatching { repository.refresh(snap.leagues, snap.teams) }
        }
    }

    /** Spin up the live-score foreground service when something is in play. */
    private fun startLiveTrackingIfNeeded() {
        val all = repository.leagueMatches.value.flatMap { it.matches }
        if (all.any { it.state == MatchState.LIVE }) {
            LiveScoreService.start(getApplication())
        }
        // Schedule kickoff reminders for upcoming favorites.
        com.example.matcha.notifications.MatchReminders.schedule(
            getApplication(), all, System.currentTimeMillis(),
        )
    }

    fun showStreams(match: Match) {
        _streamSheet.value = StreamSheetState(match, loading = true)
        viewModelScope.launch {
            val settings = runCatching { settingsStore.settings.first() }.getOrNull()
            // Resolve IPTV (native-playable, listed first) and Streamed concurrently.
            val iptv = async {
                val m3u = settings?.iptvM3uUrl.orEmpty()
                if (m3u.isBlank()) emptyList()
                else runCatching { iptvResolver.resolve(match, m3u, settings?.iptvEpgUrl) }.getOrDefault(emptyList())
            }
            val streamed = async { runCatching { resolver.resolve(match) }.getOrDefault(emptyList()) }
            val options = (iptv.await() + streamed.await()).distinctBy { it.url }
            // Ignore if the user already dismissed or opened another match.
            if (_streamSheet.value?.match?.id == match.id) {
                _streamSheet.value = StreamSheetState(match, loading = false, options = options)
            }
        }
    }

    fun dismissStreams() {
        _streamSheet.value = null
    }

    private data class FavoriteSnapshot(
        val leagues: Set<String> = emptySet(),
        val teams: Set<String> = emptySet(),
    )
}

data class StreamSheetState(
    val match: Match,
    val loading: Boolean,
    val options: List<StreamOption> = emptyList(),
)

sealed interface ScoresUiState {
    data object Loading : ScoresUiState
    data object Empty : ScoresUiState
    data class Success(val groups: List<LeagueMatches>) : ScoresUiState
}
