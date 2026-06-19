package com.example.matcha

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.core.content.ContextCompat
import com.example.matcha.theme.MatchaGradientBottom
import com.example.matcha.theme.MatchaGradientTop
import com.example.matcha.theme.MatchaTheme

class MainActivity : ComponentActivity() {

  private val requestNotifications =
    registerForActivityResult(ActivityResultContracts.RequestPermission()) { /* best-effort */ }

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)

    maybeRequestNotificationPermission()
    enableEdgeToEdge()
    setContent {
      val settings by com.example.matcha.data.SettingsStore(this)
        .settings.collectAsState(initial = com.example.matcha.data.MatchaSettings())
      val dark = when (settings.themeMode) {
        com.example.matcha.data.ThemeMode.SYSTEM -> androidx.compose.foundation.isSystemInDarkTheme()
        com.example.matcha.data.ThemeMode.DARK -> true
        com.example.matcha.data.ThemeMode.LIGHT -> false
      }
      MatchaTheme(darkTheme = dark, dynamicColor = settings.dynamicColor) {
        Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
          MainNavigation(startRoute = intent?.data?.host)
        }
      }
    }
  }

  /** Live-match notifications need POST_NOTIFICATIONS on Android 13+. */
  private fun maybeRequestNotificationPermission() {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
    val granted = ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) ==
      PackageManager.PERMISSION_GRANTED
    if (!granted) requestNotifications.launch(Manifest.permission.POST_NOTIFICATIONS)
  }
}
