package com.example.matcha.data

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

private val Context.settingsDataStore: DataStore<Preferences> by preferencesDataStore(name = "matcha_settings")

enum class ThemeMode { SYSTEM, DARK, LIGHT }

data class MatchaSettings(
    val themeMode: ThemeMode = ThemeMode.DARK,
    val dynamicColor: Boolean = false,
)

/** App-wide preferences (theme mode, Material You) persisted via DataStore. */
class SettingsStore(private val context: Context) {

    private object Keys {
        val THEME = stringPreferencesKey("theme_mode")
        val DYNAMIC = booleanPreferencesKey("dynamic_color")
        val ONBOARDED = booleanPreferencesKey("onboarded")
    }

    val onboarded: Flow<Boolean> = context.settingsDataStore.data.map { it[Keys.ONBOARDED] ?: false }

    suspend fun setOnboarded() {
        context.settingsDataStore.edit { it[Keys.ONBOARDED] = true }
    }

    val settings: Flow<MatchaSettings> = context.settingsDataStore.data.map { p ->
        MatchaSettings(
            themeMode = runCatching { ThemeMode.valueOf(p[Keys.THEME] ?: "DARK") }.getOrDefault(ThemeMode.DARK),
            dynamicColor = p[Keys.DYNAMIC] ?: false,
        )
    }

    suspend fun setThemeMode(mode: ThemeMode) {
        context.settingsDataStore.edit { it[Keys.THEME] = mode.name }
    }

    suspend fun setDynamicColor(enabled: Boolean) {
        context.settingsDataStore.edit { it[Keys.DYNAMIC] = enabled }
    }
}
