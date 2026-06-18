package com.example.matcha

import android.app.Application
import com.example.matcha.data.FavoritesStore
import com.example.matcha.sync.WearFavoritesPublisher
import com.example.matcha.widget.WidgetUpdateWorker
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

/** Application entry point; schedules widget refresh and mirrors favorites to the watch. */
class MatchaApp : Application() {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    override fun onCreate() {
        super.onCreate()
        WidgetUpdateWorker.schedule(this)

        // Mirror favorite leagues to the Wear Data Layer as they change.
        val favorites = FavoritesStore(this)
        scope.launch {
            favorites.favoriteLeagueIds.collectLatest { ids ->
                WearFavoritesPublisher.publish(this@MatchaApp, ids)
            }
        }
    }
}
