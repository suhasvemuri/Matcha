package com.example.matcha.notifications

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.example.matcha.MainActivity
import com.example.matcha.R
import com.example.matcha.data.Match

/**
 * Posts and updates an ongoing "live activity"-style notification per live
 * match. Updating in place (stable id per match) keeps a single, glanceable
 * scoreline that ticks as the score changes — Android's analogue to iOS Live
 * Activities, achievable back to API 26.
 */
class LiveMatchNotifier(private val context: Context) {

    private val manager = NotificationManagerCompat.from(context)

    fun ensureChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Live matches",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Ongoing scores for your favorite live matches"
                setShowBadge(false)
            }
            val sys = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            sys.createNotificationChannel(channel)
        }
    }

    /** A summary notification used as the foreground-service anchor. */
    fun summary(liveCount: Int) =
        NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_matcha)
            .setContentTitle("Matcha")
            .setContentText(
                if (liveCount == 0) "Watching for live matches…"
                else "$liveCount live ${if (liveCount == 1) "match" else "matches"}",
            )
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(openAppIntent())
            .setGroup(GROUP_KEY)
            .setGroupSummary(true)
            .build()

    fun notifyMatch(match: Match) {
        if (!canPost()) return
        val title = "${match.home.shortName} ${match.home.score ?: ""} – ${match.away.score ?: ""} ${match.away.shortName}"
        val body = buildString {
            append(match.leagueName)
            if (match.statusDetail.isNotBlank()) append(" · ${match.statusDetail}")
        }
        val chip = buildString {
            append(match.home.abbreviation.ifBlank { match.home.shortName })
            append(" ")
            append(match.home.score?.substringBefore(" (")?.trim().orEmpty().ifBlank { "0" })
            append("-")
            append(match.away.score?.substringBefore(" (")?.trim().orEmpty().ifBlank { "0" })
            append(" ")
            append(match.away.abbreviation.ifBlank { match.away.shortName })
        }

        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_matcha)
            .setContentTitle(title)
            .setContentText(body)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(openAppIntent())
            // Android 16 Live Update: surface as a promoted ongoing notification
            // (status-bar chip + lock screen). No-op/normal ongoing on older OS.
            .setRequestPromotedOngoing(true)
            .setShortCriticalText(chip)

        applyMatchStyle(builder, match)
        manager.notify(match.id.hashCode(), builder.build())
    }

    /** ProgressStyle shows the match minute as a live bar; falls back to BigText. */
    private fun applyMatchStyle(builder: NotificationCompat.Builder, match: Match) {
        val minute = match.statusDetail.takeWhile { it.isDigit() }.toIntOrNull()
        if (match.sport == com.example.matcha.data.Sport.SOCCER && minute != null) {
            val total = 90
            val progress = minute.coerceIn(0, total)
            val style = NotificationCompat.ProgressStyle()
                .setProgress(progress)
                .setProgressSegments(listOf(NotificationCompat.ProgressStyle.Segment(total)))
            builder.setStyle(style)
        } else {
            builder.setStyle(NotificationCompat.BigTextStyle().bigText("${match.home.name} vs ${match.away.name}"))
        }
    }

    fun clearMatch(matchId: String) {
        manager.cancel(matchId.hashCode())
    }

    private fun canPost(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) ==
                android.content.pm.PackageManager.PERMISSION_GRANTED
        } else true

    private fun openAppIntent(): PendingIntent {
        val intent = Intent().apply {
            component = ComponentName(context, MainActivity::class.java)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        return PendingIntent.getActivity(
            context, 0, intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }

    companion object {
        const val CHANNEL_ID = "matcha_live_matches"
        const val GROUP_KEY = "matcha_live_group"
        const val SUMMARY_ID = 1001
    }
}
