package com.example.matcha.wear.data

import android.content.Context

/** Tiny SharedPreferences store for favorites synced from the phone. */
object WearFavoritesStore {
    private const val PREFS = "matcha_wear_prefs"
    private const val KEY = "synced_leagues"

    fun save(context: Context, encodedLeagues: Set<String>) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putStringSet(KEY, encodedLeagues)
            .apply()
    }

    /** Returns decoded synced leagues, or the curated defaults if none synced. */
    fun load(context: Context): List<WearLeague> {
        val encoded = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getStringSet(KEY, emptySet()).orEmpty()
        val decoded = WearLeagues.decode(encoded)
        return decoded.ifEmpty { WearLeagues.defaults }
    }
}
