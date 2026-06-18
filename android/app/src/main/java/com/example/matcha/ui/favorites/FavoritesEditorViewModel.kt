package com.example.matcha.ui.favorites

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.example.matcha.data.FavoritesStore
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

class FavoritesEditorViewModel(app: Application) : AndroidViewModel(app) {

    private val store = FavoritesStore(app)

    val favoriteLeagueIds: StateFlow<Set<String>> =
        store.favoriteLeagueIds.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptySet())

    val favoriteTeamNames: StateFlow<Set<String>> =
        store.favoriteTeamNames.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptySet())

    fun setLeague(id: String, favorite: Boolean) {
        viewModelScope.launch { store.setLeagueFavorite(id, favorite) }
    }

    fun addTeam(name: String) {
        viewModelScope.launch { store.setTeamFavorite(name, true) }
    }

    fun removeTeam(name: String) {
        viewModelScope.launch { store.setTeamFavorite(name, false) }
    }
}
