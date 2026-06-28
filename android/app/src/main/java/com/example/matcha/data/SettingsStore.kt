package com.example.matcha.data

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

private val Context.settingsDataStore: DataStore<Preferences> by preferencesDataStore(name = "matcha_settings")

enum class ThemeMode { SYSTEM, DARK, LIGHT }

/** How often the live scores screen quietly re-fetches while a match is on. */
enum class RefreshInterval(val seconds: Int, val label: String) {
    FAST(10, "10 seconds"),
    NORMAL(30, "30 seconds"),
    RELAXED(60, "1 minute"),
    BATTERY(300, "5 minutes");

    companion object {
        val DEFAULT = NORMAL
        fun fromSeconds(s: Int): RefreshInterval = entries.firstOrNull { it.seconds == s } ?: DEFAULT
    }
}

data class MatchaSettings(
    val themeMode: ThemeMode = ThemeMode.DARK,
    val dynamicColor: Boolean = false,
    val refreshInterval: RefreshInterval = RefreshInterval.DEFAULT,
    /** Optional user IPTV playlist + EPG for native "where to watch" streams. */
    val iptvM3uUrl: String = "",
    val iptvEpgUrl: String = "",
)

/** App-wide preferences (theme mode, Material You) persisted via DataStore. */
class SettingsStore(private val context: Context) {

    private object Keys {
        val THEME = stringPreferencesKey("theme_mode")
        val DYNAMIC = booleanPreferencesKey("dynamic_color")
        val REFRESH = intPreferencesKey("refresh_seconds")
        val IPTV_M3U = stringPreferencesKey("iptv_m3u_url")
        val IPTV_EPG = stringPreferencesKey("iptv_epg_url")
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
            refreshInterval = RefreshInterval.fromSeconds(p[Keys.REFRESH] ?: RefreshInterval.DEFAULT.seconds),
            iptvM3uUrl = p[Keys.IPTV_M3U] ?: "",
            iptvEpgUrl = p[Keys.IPTV_EPG] ?: "",
        )
    }

    suspend fun setThemeMode(mode: ThemeMode) {
        context.settingsDataStore.edit { it[Keys.THEME] = mode.name }
    }

    suspend fun setDynamicColor(enabled: Boolean) {
        context.settingsDataStore.edit { it[Keys.DYNAMIC] = enabled }
    }

    suspend fun setRefreshInterval(interval: RefreshInterval) {
        context.settingsDataStore.edit { it[Keys.REFRESH] = interval.seconds }
    }

    suspend fun setIptvM3uUrl(url: String) {
        context.settingsDataStore.edit { it[Keys.IPTV_M3U] = url.trim() }
    }

    suspend fun setIptvEpgUrl(url: String) {
        context.settingsDataStore.edit { it[Keys.IPTV_EPG] = url.trim() }
    }
}
