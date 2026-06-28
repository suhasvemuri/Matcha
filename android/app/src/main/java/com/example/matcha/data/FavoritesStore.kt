package com.example.matcha.data

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringSetPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

private val Context.dataStore: DataStore<Preferences> by preferencesDataStore(name = "matcha_favorites")

/**
 * Persists the user's favorite leagues (and team-name filters) via DataStore.
 * Favorite team names are matched case-insensitively against match-ups so a
 * fan can follow "India" or "Arsenal" across any competition.
 */
class FavoritesStore(private val context: Context) {

    private object Keys {
        val LEAGUES = stringSetPreferencesKey("favorite_league_ids")
        val TEAMS = stringSetPreferencesKey("favorite_team_names")
    }

    val favoriteLeagueIds: Flow<Set<String>> = context.dataStore.data.map { prefs ->
        prefs[Keys.LEAGUES] ?: Leagues.defaultFavoriteIds
    }

    val favoriteTeamNames: Flow<Set<String>> = context.dataStore.data.map { prefs ->
        prefs[Keys.TEAMS] ?: emptySet()
    }

    suspend fun setLeagueFavorite(id: String, favorite: Boolean) {
        context.dataStore.edit { prefs ->
            val current = (prefs[Keys.LEAGUES] ?: Leagues.defaultFavoriteIds).toMutableSet()
            if (favorite) current.add(id) else current.remove(id)
            prefs[Keys.LEAGUES] = current
        }
    }

    suspend fun setTeamFavorite(name: String, favorite: Boolean) {
        val clean = name.trim()
        if (clean.isEmpty()) return
        context.dataStore.edit { prefs ->
            val current = (prefs[Keys.TEAMS] ?: emptySet()).toMutableSet()
            if (favorite) current.add(clean) else current.remove(clean)
            prefs[Keys.TEAMS] = current
        }
    }
}
