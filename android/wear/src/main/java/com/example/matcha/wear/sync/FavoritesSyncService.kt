package com.example.matcha.wear.sync

import com.example.matcha.wear.data.WearFavoritesStore
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.WearableListenerService

/**
 * Receives favorite leagues pushed from the phone (`/matcha/favorites`) and
 * persists them locally so the watch app and tile mirror the phone's picks.
 */
class FavoritesSyncService : WearableListenerService() {

    override fun onDataChanged(dataEvents: DataEventBuffer) {
        for (event in dataEvents) {
            if (event.type != DataEvent.TYPE_CHANGED) continue
            val item = event.dataItem
            if (item.uri.path != PATH) continue
            val map = DataMapItem.fromDataItem(item).dataMap
            val leagues = map.getStringArrayList(KEY_LEAGUES)?.toSet() ?: emptySet()
            WearFavoritesStore.save(this, leagues)
        }
    }

    companion object {
        private const val PATH = "/matcha/favorites"
        private const val KEY_LEAGUES = "leagues"
    }
}
