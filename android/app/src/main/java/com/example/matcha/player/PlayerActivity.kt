package com.example.matcha.player

import android.annotation.SuppressLint
import android.app.PictureInPictureParams
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.util.Rational
import android.view.View
import android.view.ViewGroup
import android.webkit.WebChromeClient
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import androidx.activity.ComponentActivity
import androidx.annotation.OptIn
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import com.google.android.gms.cast.framework.CastContext

/**
 * Full-screen, immersive stream player with Picture-in-Picture.
 *
 * - Direct streams (.m3u8/.mpd/.mp4/.ts) play in ExoPlayer (Media3) and can be
 *   cast to a Google Cast device.
 * - Embed pages (e.g. streamed.st's embed.st) play in a clean full-screen
 *   WebView — the common case for the Streamed provider.
 */
@OptIn(UnstableApi::class)
class PlayerActivity : ComponentActivity() {

    private var exoPlayer: ExoPlayer? = null
    private var playerView: PlayerView? = null
    private var webView: WebView? = null

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val url = intent.getStringExtra(EXTRA_URL).orEmpty()
        if (url.isBlank()) { finish(); return }

        WindowCompat.setDecorFitsSystemWindows(window, false)
        hideSystemBars()

        val root = FrameLayout(this).apply {
            setBackgroundColor(0xFF000000.toInt())
            layoutParams = ViewGroup.LayoutParams(MATCH, MATCH)
        }
        setContentView(root)

        if (isDirectStream(url)) {
            setupExoPlayer(root, url)
        } else {
            setupWebView(root, url)
        }
    }

    private fun setupExoPlayer(root: FrameLayout, url: String) {
        runCatching { CastContext.getSharedInstance(this) } // warm up cast if available
        val player = ExoPlayer.Builder(this).build().also { exoPlayer = it }
        val view = PlayerView(this).apply {
            this.player = player
            layoutParams = FrameLayout.LayoutParams(MATCH, MATCH)
        }
        playerView = view
        root.addView(view)
        player.setMediaItem(MediaItem.fromUri(url))
        player.playWhenReady = true
        player.prepare()
    }

    private fun setupWebView(root: FrameLayout, url: String) {
        val web = WebView(this).apply {
            layoutParams = FrameLayout.LayoutParams(MATCH, MATCH)
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.mediaPlaybackRequiresUserGesture = false
            settings.loadWithOverviewMode = true
            settings.useWideViewPort = true
            webViewClient = WebViewClient()
            webChromeClient = WebChromeClient() // enables native fullscreen video
        }
        webView = web
        root.addView(web)
        web.loadUrl(url)
    }

    // --- Picture-in-Picture -------------------------------------------------

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        enterPip()
    }

    private fun enterPip() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        if (!packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)) return
        if (exoPlayer?.isPlaying != true && webView == null) return
        val params = PictureInPictureParams.Builder()
            .setAspectRatio(Rational(16, 9))
            .build()
        runCatching { enterPictureInPictureMode(params) }
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: android.content.res.Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        // Hide player chrome in PiP for a clean thumbnail.
        playerView?.useController = !isInPictureInPictureMode
    }

    private fun hideSystemBars() {
        val controller = WindowInsetsControllerCompat(window, window.decorView)
        controller.hide(WindowInsetsCompat.Type.systemBars())
        controller.systemBarsBehavior =
            WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
    }

    override fun onStop() {
        super.onStop()
        if (!isInPictureInPictureModeCompat()) {
            exoPlayer?.pause()
            webView?.onPause()
        }
    }

    override fun onResume() {
        super.onResume()
        webView?.onResume()
    }

    private fun isInPictureInPictureModeCompat(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && isInPictureInPictureMode

    override fun onDestroy() {
        exoPlayer?.release()
        exoPlayer = null
        (webView?.parent as? ViewGroup)?.removeView(webView)
        webView?.destroy()
        webView = null
        super.onDestroy()
    }

    companion object {
        private const val MATCH = ViewGroup.LayoutParams.MATCH_PARENT
        const val EXTRA_URL = "extra_url"
        const val EXTRA_TITLE = "extra_title"

        private val DIRECT = Regex("""\.(m3u8|mpd|mp4|ts|m4s)(\?.*)?$""", RegexOption.IGNORE_CASE)
        fun isDirectStream(url: String): Boolean = DIRECT.containsMatchIn(url)

        fun start(context: Context, url: String, title: String) {
            context.startActivity(
                Intent(context, PlayerActivity::class.java)
                    .putExtra(EXTRA_URL, url)
                    .putExtra(EXTRA_TITLE, title)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        }
    }
}
