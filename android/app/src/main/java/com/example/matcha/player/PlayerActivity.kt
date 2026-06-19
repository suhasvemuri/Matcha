package com.example.matcha.player

import android.annotation.SuppressLint
import android.app.PictureInPictureParams
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Rational
import android.view.Gravity
import android.view.ViewGroup
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import android.widget.ProgressBar
import androidx.activity.ComponentActivity
import androidx.annotation.OptIn
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.media3.common.MediaItem
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.hls.HlsMediaSource
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.PlayerView
import com.google.android.gms.cast.framework.CastContext

/**
 * Immersive stream player with Picture-in-Picture.
 *
 * Plays natively in ExoPlayer (Media3): direct streams play immediately; for
 * embed pages (streamed.st's embed.st) an offscreen WebView is loaded and its
 * dynamically-fetched HLS playlist (.m3u8) is intercepted and handed to
 * ExoPlayer — so the match plays in-app, not on the website. Falls back to
 * the WebView player only if no playlist can be extracted.
 */
@OptIn(UnstableApi::class)
class PlayerActivity : ComponentActivity() {

    private var exoPlayer: ExoPlayer? = null
    private var playerView: PlayerView? = null
    private var webView: WebView? = null
    private var spinner: ProgressBar? = null
    private lateinit var root: FrameLayout

    private var nativePlaying = false
    private var extractionDone = false
    private val main = Handler(Looper.getMainLooper())

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val url = intent.getStringExtra(EXTRA_URL).orEmpty()
        if (url.isBlank()) { finish(); return }
        runCatching { CastContext.getSharedInstance(this) }

        WindowCompat.setDecorFitsSystemWindows(window, false)
        hideSystemBars()

        root = FrameLayout(this).apply {
            setBackgroundColor(0xFF000000.toInt())
            layoutParams = ViewGroup.LayoutParams(MATCH, MATCH)
        }
        setContentView(root)
        spinner = ProgressBar(this).apply {
            layoutParams = FrameLayout.LayoutParams(WRAP, WRAP, Gravity.CENTER)
        }
        root.addView(spinner)

        if (isDirectStream(url)) {
            if (isSafeMediaUrl(url)) playNative(url, emptyMap()) else finish()
        } else {
            setupEmbedExtraction(url)
        }
    }

    /** Play an HLS/stream URL natively in ExoPlayer. */
    private fun playNative(url: String, headers: Map<String, String>) {
        if (nativePlaying) return
        nativePlaying = true
        spinner?.let { root.removeView(it) }

        val httpFactory = DefaultHttpDataSource.Factory()
            .setAllowCrossProtocolRedirects(true)
            .setUserAgent(DESKTOP_UA)
            .setDefaultRequestProperties(
                buildMap {
                    put("Referer", "https://embed.st/")
                    headers["Referer"]?.let { put("Referer", it) }
                    headers["Origin"]?.let { put("Origin", it) }
                },
            )
        val player = ExoPlayer.Builder(this)
            .setMediaSourceFactory(DefaultMediaSourceFactory(httpFactory))
            .build()
            .also { exoPlayer = it }

        val view = PlayerView(this).apply {
            this.player = player
            layoutParams = FrameLayout.LayoutParams(MATCH, MATCH)
            setShowNextButton(false)
            setShowPreviousButton(false)
        }
        playerView = view
        root.addView(view)

        // Mute/hide the extraction WebView so there's no double audio.
        webView?.let { wv ->
            wv.evaluateJavascript(
                "document.querySelectorAll('video').forEach(v=>{v.muted=true;v.pause();});", null,
            )
            wv.visibility = android.view.View.GONE
        }

        val media = if (url.contains(".m3u8")) {
            HlsMediaSource.Factory(httpFactory).createMediaSource(MediaItem.fromUri(url))
        } else {
            null
        }
        if (media != null) player.setMediaSource(media) else player.setMediaItem(MediaItem.fromUri(url))
        player.playWhenReady = true
        player.prepare()
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun setupEmbedExtraction(embedUrl: String) {
        val web = WebView(this).apply {
            layoutParams = FrameLayout.LayoutParams(MATCH, MATCH)
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.mediaPlaybackRequiresUserGesture = false
            settings.loadWithOverviewMode = true
            settings.useWideViewPort = true
            settings.userAgentString = DESKTOP_UA
            visibility = android.view.View.INVISIBLE // hidden until we decide
            webChromeClient = WebChromeClient()
            webViewClient = object : WebViewClient() {
                override fun shouldInterceptRequest(
                    view: WebView?,
                    request: WebResourceRequest?,
                ): WebResourceResponse? {
                    val u = request?.url?.toString()
                    if (u != null && !extractionDone && u.contains(".m3u8") && !u.contains("/ad") &&
                        isSafeMediaUrl(u)
                    ) {
                        extractionDone = true
                        val headers = request.requestHeaders ?: emptyMap()
                        main.post { playNative(u, headers) }
                    }
                    return super.shouldInterceptRequest(view, request)
                }
            }
        }
        webView = web
        root.addView(web, 0) // behind the spinner
        web.loadUrl(embedUrl)

        // Fallback: if no playlist is intercepted, show the WebView player.
        main.postDelayed({
            if (!nativePlaying) {
                extractionDone = true
                spinner?.let { root.removeView(it) }
                web.visibility = android.view.View.VISIBLE
            }
        }, EXTRACT_TIMEOUT_MS)
    }

    // --- Picture-in-Picture -------------------------------------------------

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        enterPip()
    }

    private fun enterPip() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        if (!packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)) return
        val params = PictureInPictureParams.Builder().setAspectRatio(Rational(16, 9)).build()
        runCatching { enterPictureInPictureMode(params) }
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: android.content.res.Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        playerView?.useController = !isInPictureInPictureMode
    }

    private fun hideSystemBars() {
        val controller = WindowInsetsControllerCompat(window, window.decorView)
        controller.hide(WindowInsetsCompat.Type.systemBars())
        controller.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
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
        main.removeCallbacksAndMessages(null)
        exoPlayer?.release()
        exoPlayer = null
        (webView?.parent as? ViewGroup)?.removeView(webView)
        webView?.destroy()
        webView = null
        super.onDestroy()
    }

    companion object {
        private const val MATCH = ViewGroup.LayoutParams.MATCH_PARENT
        private const val WRAP = ViewGroup.LayoutParams.WRAP_CONTENT
        private const val EXTRACT_TIMEOUT_MS = 18_000L
        private const val DESKTOP_UA =
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36"
        const val EXTRA_URL = "extra_url"
        const val EXTRA_TITLE = "extra_title"

        private val DIRECT = Regex("""\.(m3u8|mpd|mp4|ts|m4s)(\?.*)?$""", RegexOption.IGNORE_CASE)
        fun isDirectStream(url: String): Boolean = DIRECT.containsMatchIn(url)

        /**
         * Guards against device-side SSRF via an intercepted URL: only play
         * media over HTTPS from a public host (never loopback / private /
         * link-local addresses that could reach internal services).
         */
        fun isSafeMediaUrl(url: String): Boolean {
            val uri = runCatching { java.net.URI(url) }.getOrNull() ?: return false
            if (!uri.scheme.equals("https", ignoreCase = true)) return false
            val host = uri.host?.lowercase()?.trim('[', ']')?.ifBlank { null } ?: return false
            return !isPrivateOrLocalHost(host)
        }

        private fun isPrivateOrLocalHost(host: String): Boolean {
            if (host == "localhost" || host.endsWith(".local") || host.endsWith(".internal")) return true
            // IPv4 loopback / private / link-local
            if (host == "0.0.0.0" || host.startsWith("127.") || host.startsWith("10.") ||
                host.startsWith("192.168.") || host.startsWith("169.254.")
            ) return true
            if (host.startsWith("172.")) {
                val second = host.split(".").getOrNull(1)?.toIntOrNull()
                if (second != null && second in 16..31) return true
            }
            // IPv6 loopback / unique-local / link-local
            if (host == "::1" || host.startsWith("fc") || host.startsWith("fd") || host.startsWith("fe80")) return true
            return false
        }

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
