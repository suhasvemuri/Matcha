package com.example.matcha.ui.main

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.example.matcha.data.FavoritesStore
import com.example.matcha.data.LeagueMatches
import com.example.matcha.data.MatchaRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

class MainScreenViewModel(app: Application) : AndroidViewModel(app) {

    private val favorites = FavoritesStore(app)
    private val repository = MatchaRepository.get(app)

    private val _isRefreshing = MutableStateFlow(false)
    val isRefreshing: StateFlow<Boolean> = _isRefreshing.asStateFlow()

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
        }
    }

    private data class FavoriteSnapshot(
        val leagues: Set<String> = emptySet(),
        val teams: Set<String> = emptySet(),
    )
}

sealed interface ScoresUiState {
    data object Loading : ScoresUiState
    data object Empty : ScoresUiState
    data class Success(val groups: List<LeagueMatches>) : ScoresUiState
}
