package com.example.matcha.notifications

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.compose.ui.graphics.toArgb
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.graphics.drawable.IconCompat
import com.example.matcha.MainActivity
import com.example.matcha.R
import com.example.matcha.data.Match
import com.example.matcha.data.Sport
import com.example.matcha.theme.CompetitionThemes

/**
 * Posts and updates an ongoing "live activity"-style notification per live
 * match. Updating in place (stable id per match) keeps a single, glanceable
 * scoreline that ticks as the score changes — Android's analogue to iOS Live
 * Activities, promoted to the Android 16 status-bar chip via Live Updates.
 *
 * Design follows the Live Updates guidance: a promoted ongoing notification
 * (status-bar chip + uncollapsible lock-screen card) styled with ProgressStyle
 * to visualize the match clock, an accent color per competition, and a short
 * critical text that surfaces the live score in the chip.
 *
 * This also drives the Samsung One UI 7 Now Bar: androidx writes the
 * `requestPromotedOngoing`, `shortCriticalText` and ProgressStyle data as compat
 * extras on API < 36, which is exactly what One UI 7 (Android 15) reads to render
 * the live score as a Now Bar pill — no Samsung-specific SDK required.
 */
class LiveMatchNotifier(private val context: Context) {

    private val manager = NotificationManagerCompat.from(context)

    fun ensureChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // DEFAULT (not LOW/MIN) so the notification is eligible for promotion
            // to the status-bar chip; we keep score updates silent so it doesn't
            // buzz on every poll — goals get their own high-importance channel.
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Live matches",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                description = "Ongoing scores for your favorite live matches"
                setShowBadge(false)
                enableVibration(false)
                setSound(null, null)
            }
            val goals = NotificationChannel(
                GOAL_CHANNEL_ID,
                "Goal alerts",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply { description = "Alerts when a team scores in your live matches" }
            val sys = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            sys.createNotificationChannel(channel)
            sys.createNotificationChannel(goals)
        }
    }

    /** A heads-up alert when a goal is scored in a tracked match. */
    fun notifyGoal(match: Match) {
        if (!canPost()) return
        val accent = accentArgb(match)
        val scoreLine = "${match.home.shortName}  ${compactScore(match)}  ${match.away.shortName}"
        val title = when (match.sport) {
            Sport.CRICKET -> "Wicket / boundary — ${match.leagueName}"
            else -> "GOAL — ${match.leagueName}"
        }
        val n = NotificationCompat.Builder(context, GOAL_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_matcha)
            .setColor(accent)
            .setContentTitle(title)
            .setContentText(scoreLine)
            .setStyle(NotificationCompat.BigTextStyle().bigText(scoreLine).setBigContentTitle(title))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_EVENT)
            .setAutoCancel(true)
            .setContentIntent(openAppIntent())
            .build()
        manager.notify("goal-${match.id}".hashCode(), n)
    }

    /** A transient anchor notification shown before the first poll resolves. */
    fun summary(liveCount: Int): Notification =
        NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_matcha)
            .setContentTitle("Matcha")
            .setContentText("Watching for live matches…")
            .setOngoing(true)
            .setSilent(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(openAppIntent())
            .build()

    /** Post a secondary live match, unless the user swiped it away recently. */
    fun notifyMatch(match: Match) {
        if (!canPost()) return
        if (DismissedNotifications.isDismissed(context, match.id, System.currentTimeMillis())) return
        manager.notify(match.id.hashCode(), buildMatchNotification(match))
    }

    /** Builds a promotable (Android 16 Live Update) notification for a match. */
    fun buildMatchNotification(match: Match): Notification {
        val accent = accentArgb(match)
        val title = "${teamLabel(match.home.abbreviation, match.home.shortName)} " +
            "${compactScore(match)} " +
            teamLabel(match.away.abbreviation, match.away.shortName)
        val body = buildString {
            append(match.leagueName)
            if (match.statusDetail.isNotBlank()) append(" · ${match.statusDetail}")
            match.venue?.takeIf { it.isNotBlank() }?.let { append(" · $it") }
        }

        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_matcha)
            .setColor(accent)
            .setContentTitle(title)
            .setContentText(body)
            .setSubText(match.leagueName)
            .setOngoing(true)
            .setSilent(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(openAppIntent())
            .setDeleteIntent(dismissIntent(match.id))
            // Android 16 Live Update: surface as a promoted ongoing notification
            // (status-bar chip + lock screen). No-op/normal ongoing on older OS.
            .setRequestPromotedOngoing(true)
            .setShortCriticalText(chipText(match))

        applyMatchStyle(builder, match, accent)
        return builder.build()
    }

    /**
     * ProgressStyle visualizes the soccer match clock as a two-segment bar
     * (first/second half, team-tinted) with HT and FT markers and a ball that
     * tracks the live minute. Other sports fall back to a rich BigText panel.
     */
    private fun applyMatchStyle(builder: NotificationCompat.Builder, match: Match, accent: Int) {
        val minute = match.statusDetail.takeWhile { it.isDigit() }.toIntOrNull()
        if (match.sport == Sport.SOCCER && minute != null) {
            val homeColor = teamColor(match.home.colorArgb, accent)
            val awayColor = teamColor(match.away.colorArgb, accent)
            val firstHalf = NotificationCompat.ProgressStyle.Segment(45).setColor(homeColor)
            val secondHalf = NotificationCompat.ProgressStyle.Segment(45).setColor(awayColor)
            val segments = mutableListOf(firstHalf, secondHalf)
            // Stoppage time beyond 90' extends the bar so the ball never pins.
            val extra = (minute - 90).coerceAtLeast(0)
            if (extra > 0) segments.add(NotificationCompat.ProgressStyle.Segment(extra).setColor(accent))
            val max = 90 + extra

            val style = NotificationCompat.ProgressStyle()
                .setStyledByProgress(false)
                .setProgressSegments(segments)
                .setProgressPoints(
                    listOf(
                        NotificationCompat.ProgressStyle.Point(45).setColor(0xFFE0E0E0.toInt()),
                        NotificationCompat.ProgressStyle.Point(90).setColor(0xFFFFFFFF.toInt()),
                    ),
                )
                .setProgress(minute.coerceIn(0, max))
                .setProgressTrackerIcon(IconCompat.createWithResource(context, R.drawable.ic_ball))
                // Leading brand glyph on the Samsung One UI 7 Now Bar pill.
                .setProgressStartIcon(IconCompat.createWithResource(context, R.drawable.ic_stat_matcha))
            builder.setStyle(style)
        } else {
            val detail = buildString {
                append("${match.home.name} ${match.home.score ?: ""}".trim())
                append("\n${match.away.name} ${match.away.score ?: ""}".trimEnd())
                if (match.statusDetail.isNotBlank()) append("\n${match.statusDetail}")
            }
            builder.setStyle(NotificationCompat.BigTextStyle().bigText(detail))
        }
    }

    fun clearMatch(matchId: String) {
        manager.cancel(matchId.hashCode())
        DismissedNotifications.clear(context, matchId)
    }

    // --- formatting helpers -------------------------------------------------

    /** Compact "2-1" score for chips/titles, stripping any "(pens)" suffix. */
    private fun compactScore(match: Match): String {
        val h = match.home.score?.substringBefore(" (")?.trim().orEmpty().ifBlank { "0" }
        val a = match.away.score?.substringBefore(" (")?.trim().orEmpty().ifBlank { "0" }
        return "$h-$a"
    }

    /** Status-bar chip: minute + score where short, e.g. "67' 2-1" / "HT 2-1". */
    private fun chipText(match: Match): String {
        val clock = when {
            match.statusDetail.equals("HT", ignoreCase = true) -> "HT"
            match.statusDetail.firstOrNull()?.isDigit() == true ->
                match.statusDetail.takeWhile { it.isDigit() || it == '+' } + "'"
            else -> ""
        }
        val score = compactScore(match)
        return if (clock.isNotBlank()) "$clock $score" else score
    }

    private fun teamLabel(abbr: String, short: String): String =
        abbr.ifBlank { short }.take(4).uppercase()

    private fun accentArgb(match: Match): Int =
        CompetitionThemes.forLeague(match.leagueId).accent.toArgb()

    /** Force a usable opaque color from a team's brand color, else the accent. */
    private fun teamColor(argb: Long?, fallback: Int): Int =
        argb?.let { (it or 0xFF000000L).toInt() } ?: fallback

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

    private fun dismissIntent(matchId: String): PendingIntent {
        val intent = Intent(context, NotificationDismissReceiver::class.java).apply {
            action = NotificationDismissReceiver.ACTION_DISMISS
            putExtra(NotificationDismissReceiver.EXTRA_MATCH_ID, matchId)
        }
        return PendingIntent.getBroadcast(
            context, matchId.hashCode(), intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }

    companion object {
        const val CHANNEL_ID = "matcha_live_matches"
        const val GOAL_CHANNEL_ID = "matcha_goal_alerts"
        const val GROUP_KEY = "matcha_live_group"
        const val SUMMARY_ID = 1001
    }
}
