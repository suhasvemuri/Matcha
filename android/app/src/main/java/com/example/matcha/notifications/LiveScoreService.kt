package com.example.matcha.notifications

import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import com.example.matcha.data.FavoritesStore
import com.example.matcha.data.Match
import com.example.matcha.data.MatchState
import com.example.matcha.data.MatchaRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import androidx.core.app.ServiceCompat

/**
 * Foreground service that keeps "live activity"-style notifications fresh
 * while any favorite match is in progress. Polls every [POLL_SECONDS] and
 * self-stops once nothing is live, so it never runs longer than needed.
 */
class LiveScoreService : Service() {

    private val scope = CoroutineScope(SupervisorJob())
    private var loop: Job? = null
    private lateinit var notifier: LiveMatchNotifier
    private val trackedIds = mutableSetOf<String>()

    override fun onCreate() {
        super.onCreate()
        notifier = LiveMatchNotifier(this)
        notifier.ensureChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForegroundCompat(0)
        if (loop?.isActive != true) {
            loop = scope.launch { pollLoop() }
        }
        return START_STICKY
    }

    private suspend fun pollLoop() {
        val favorites = FavoritesStore(this)
        val repo = MatchaRepository.get(this)
        while (scope.isActive) {
            val leagues = favorites.favoriteLeagueIds.first()
            val teams = favorites.favoriteTeamNames.first()
            val all = runCatching { repo.fetchOnce(leagues, teams) }.getOrDefault(emptyList())
            val live = all.filter { it.state == MatchState.LIVE }

            updateNotifications(live)

            if (live.isEmpty()) {
                stopSelfCleanly()
                return
            }
            delay(POLL_SECONDS * 1000L)
        }
    }

    private fun updateNotifications(live: List<Match>) {
        if (live.isEmpty()) return
        val liveIds = live.map { it.id }.toSet()
        // Clear finished matches we were tracking.
        (trackedIds - liveIds).forEach { notifier.clearMatch(it) }
        trackedIds.clear()
        trackedIds.addAll(liveIds)

        // Make the primary live match the foreground notification — a single,
        // standalone, promotable Live Update (not auto-grouped with a summary).
        val primary = live.first()
        startForegroundWith(notifier.buildMatchNotification(primary))
        notifier.clearMatch(primary.id) // it now lives as the FGS notification
        live.drop(1).forEach { notifier.notifyMatch(it) }
    }

    private fun startForegroundCompat(liveCount: Int) {
        startForegroundWith(notifier.summary(liveCount))
    }

    private fun startForegroundWith(notification: android.app.Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ServiceCompat.startForeground(
                this,
                LiveMatchNotifier.SUMMARY_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            startForeground(LiveMatchNotifier.SUMMARY_ID, notification)
        }
    }

    private fun stopSelfCleanly() {
        trackedIds.forEach { notifier.clearMatch(it) }
        trackedIds.clear()
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        private const val POLL_SECONDS = 45L

        /** Start tracking live matches if not already running. */
        fun start(context: Context) {
            val intent = Intent(context, LiveScoreService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }
    }
}
