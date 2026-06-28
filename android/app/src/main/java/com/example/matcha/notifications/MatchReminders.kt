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
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import com.example.matcha.MainActivity
import com.example.matcha.R
import com.example.matcha.data.Match
import com.example.matcha.data.MatchState
import java.util.concurrent.TimeUnit

/** Posts a heads-up reminder shortly before a favorited match kicks off. */
class MatchReminderWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result {
        val home = inputData.getString("home") ?: return Result.success()
        val away = inputData.getString("away") ?: return Result.success()
        val league = inputData.getString("league") ?: ""

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL, "Match reminders", NotificationManager.IMPORTANCE_DEFAULT)
                .apply { description = "Reminders before your favorite matches start" }
            (applicationContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(channel)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            applicationContext.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) !=
            android.content.pm.PackageManager.PERMISSION_GRANTED
        ) return Result.success()

        val intent = Intent().apply {
            component = ComponentName(applicationContext, MainActivity::class.java)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pi = PendingIntent.getActivity(
            applicationContext, 0, intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val n = NotificationCompat.Builder(applicationContext, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_matcha)
            .setContentTitle("⏰ Starting soon — $league")
            .setContentText("$home vs $away")
            .setAutoCancel(true)
            .setContentIntent(pi)
            .build()
        NotificationManagerCompat.from(applicationContext).notify(id.hashCode(), n)
        return Result.success()
    }

    companion object {
        private const val CHANNEL = "matcha_reminders"
    }
}

object MatchReminders {
    private const val LEAD_MS = 15 * 60 * 1000L

    /** Schedule reminders ~15 min before each upcoming favorite match (next 24h). */
    fun schedule(context: Context, matches: List<Match>, now: Long) {
        val wm = WorkManager.getInstance(context)
        matches.asSequence()
            .filter { it.state == MatchState.UPCOMING && it.kickoffEpochMs > now }
            .filter { it.kickoffEpochMs - now < 24 * 60 * 60 * 1000L }
            .forEach { m ->
                val delay = (m.kickoffEpochMs - LEAD_MS - now).coerceAtLeast(0)
                val req = OneTimeWorkRequestBuilder<MatchReminderWorker>()
                    .setInitialDelay(delay, TimeUnit.MILLISECONDS)
                    .setInputData(
                        Data.Builder()
                            .putString("home", m.home.name)
                            .putString("away", m.away.name)
                            .putString("league", m.leagueName)
                            .build(),
                    )
                    .build()
                wm.enqueueUniqueWork("reminder-${m.id}", ExistingWorkPolicy.REPLACE, req)
            }
    }
}
