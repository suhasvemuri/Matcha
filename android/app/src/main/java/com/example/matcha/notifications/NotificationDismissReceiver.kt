package com.example.matcha.notifications

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Records when the user swipes away a live-match notification so we don't
 * re-post it on the next poll — per the Live Updates guidance ("do not repost
 * what users dismissed"). Dismissals expire after [TTL_MS] so a future match
 * reusing the id (rare) isn't suppressed forever.
 */
class NotificationDismissReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val matchId = intent.getStringExtra(EXTRA_MATCH_ID) ?: return
        DismissedNotifications.markDismissed(context, matchId, System.currentTimeMillis())
    }

    companion object {
        const val ACTION_DISMISS = "com.example.matcha.NOTIFICATION_DISMISSED"
        const val EXTRA_MATCH_ID = "match_id"
    }
}

/** SharedPreferences-backed set of recently-dismissed match notifications. */
object DismissedNotifications {
    private const val PREFS = "matcha_dismissed_notifications"
    private const val TTL_MS = 4 * 60 * 60 * 1000L // 4 hours

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun markDismissed(context: Context, matchId: String, now: Long) {
        prefs(context).edit().putLong(matchId, now).apply()
    }

    /** True if the user dismissed this match's notification within the TTL. */
    fun isDismissed(context: Context, matchId: String, now: Long): Boolean {
        val at = prefs(context).getLong(matchId, 0L)
        return at != 0L && now - at < TTL_MS
    }

    /** Forget a match once it's no longer live, so it can alert again later. */
    fun clear(context: Context, matchId: String) {
        prefs(context).edit().remove(matchId).apply()
    }
}
