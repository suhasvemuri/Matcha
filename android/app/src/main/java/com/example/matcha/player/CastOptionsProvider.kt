package com.example.matcha.player

import android.content.Context
import com.google.android.gms.cast.framework.CastOptions
import com.google.android.gms.cast.framework.OptionsProvider
import com.google.android.gms.cast.framework.SessionProvider
import com.google.android.gms.cast.framework.media.CastMediaOptions

/** Google Cast configuration. Uses the Default Media Receiver. */
class CastOptionsProvider : OptionsProvider {
    override fun getCastOptions(context: Context): CastOptions =
        CastOptions.Builder()
            // Default Media Receiver app id (plays standard HLS/MP4 streams).
            .setReceiverApplicationId("CC1AD845")
            .setCastMediaOptions(
                CastMediaOptions.Builder()
                    .setMediaSessionEnabled(true)
                    .build(),
            )
            .build()

    override fun getAdditionalSessionProviders(context: Context): MutableList<SessionProvider>? = null
}
