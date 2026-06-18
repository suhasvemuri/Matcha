package com.example.matcha.sync

import android.content.Context
import com.example.matcha.data.League
import com.example.matcha.data.Leagues
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import kotlinx.coroutines.tasks.await

/**
 * Publishes the phone's favorite leagues to the Wearable Data Layer so the
 * watch app can mirror them. Each league is encoded as
 * `espnSport|slug|displayName` — self-contained, so the watch needs no copy
 * of the league catalog to fetch them.
 */
object WearFavoritesPublisher {

    private const val PATH = "/matcha/favorites"
    const val KEY_LEAGUES = "leagues"

    fun encode(league: League): String =
        "${league.espnSport}|${league.slug}|${league.displayName}"

    suspend fun publish(context: Context, favoriteLeagueIds: Set<String>) {
        val encoded = ArrayList(
            favoriteLeagueIds.mapNotNull { Leagues.byId(it) }.map(::encode),
        )
        val request = PutDataMapRequest.create(PATH).apply {
            dataMap.putStringArrayList(KEY_LEAGUES, encoded)
            // Force a data change even if the set repeats.
            dataMap.putLong("ts", encoded.hashCode().toLong())
        }.asPutDataRequest().setUrgent()

        runCatching { Wearable.getDataClient(context).putDataItem(request).await() }
    }
}
