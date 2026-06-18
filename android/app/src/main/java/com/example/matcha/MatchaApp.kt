package com.example.matcha

import android.app.Application
import com.example.matcha.widget.WidgetUpdateWorker

/** Application entry point; schedules background widget refresh. */
class MatchaApp : Application() {
    override fun onCreate() {
        super.onCreate()
        WidgetUpdateWorker.schedule(this)
    }
}
