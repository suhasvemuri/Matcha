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
import android.view.View
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
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
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
 * embed pages (streamed.st's embed.st) an offscreen WebView is loaded, autoplay
 * is nudged, and its dynamically-fetched HLS playlist (.m3u8) is intercepted and
 * handed to ExoPlayer — so the match plays in-app, not on the website.
 *
 * Streamed playlists are often token/Referer-gated, so native playback can fail
 * even after extraction. When that happens (or no playlist is found) we fall
 * back to the already-loaded WebView and let its own player run in-app — popups
 * and cross-origin ad redirects are blocked so it stays a clean player surface.
 */
@OptIn(UnstableApi::class)
class PlayerActivity : ComponentActivity() {

    private var exoPlayer: ExoPlayer? = null
    private var playerView: PlayerView? = null
    private var webView: WebView? = null
    private var spinner: ProgressBar? = null
    private var topBar: View? = null
    private var fullscreenContainer: FrameLayout? = null
    private var customViewCallback: WebChromeClient.CustomViewCallback? = null
    private lateinit var root: FrameLayout

    private var nativePlaying = false
    private var nativeHealthy = false
    private var extractionDone = false
    private var webFallbackActive = false
    private var embedHost: String? = null
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
        addTopBar(intent.getStringExtra(EXTRA_TITLE) ?: "Live stream")

        if (isDirectStream(url)) {
            if (isSafeMediaUrl(url)) playNative(url, emptyMap()) else finish()
        } else {
            embedHost = runCatching { java.net.URI(url).host }.getOrNull()
            setupEmbedExtraction(url)
        }
    }

    /** Play an HLS/stream URL natively in ExoPlayer. */
    private fun playNative(url: String, headers: Map<String, String>) {
        if (nativePlaying || webFallbackActive) return
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

        player.addListener(object : Player.Listener {
            override fun onPlayerError(error: PlaybackException) {
                // Token/Referer-gated segments or a dead manifest — drop to WebView.
                fallbackToWebView()
            }

            override fun onPlaybackStateChanged(state: Int) {
                if (state == Player.STATE_READY) nativeHealthy = true
            }
        })

        val view = PlayerView(this).apply {
            this.player = player
            layoutParams = FrameLayout.LayoutParams(MATCH, MATCH)
            setShowNextButton(false)
            setShowPreviousButton(false)
        }
        playerView = view
        root.addView(view, 0) // behind the top bar

        // Mute/hide the extraction WebView so there's no double audio.
        webView?.let { wv ->
            wv.evaluateJavascript(
                "document.querySelectorAll('video').forEach(v=>{v.muted=true;v.pause();});", null,
            )
            wv.visibility = View.GONE
        }

        val media = if (url.contains(".m3u8")) {
            HlsMediaSource.Factory(httpFactory).createMediaSource(MediaItem.fromUri(url))
        } else {
            null
        }
        if (media != null) player.setMediaSource(media) else player.setMediaItem(MediaItem.fromUri(url))
        player.playWhenReady = true
        player.prepare()

        // Watchdog: if native never becomes healthy, fall back to the WebView.
        main.postDelayed({ if (!nativeHealthy) fallbackToWebView() }, NATIVE_HEALTH_TIMEOUT_MS)
    }

    /** Native path failed or timed out — reveal the in-app WebView player. */
    private fun fallbackToWebView() {
        if (webFallbackActive) return
        webFallbackActive = true
        extractionDone = true

        exoPlayer?.let { it.stop(); it.release() }
        exoPlayer = null
        playerView?.let { root.removeView(it) }
        playerView = null
        spinner?.let { root.removeView(it) }

        val wv = webView
        if (wv == null) { finish(); return }
        wv.visibility = View.VISIBLE
        // Un-mute and (re)start playback inside the page.
        wv.evaluateJavascript(AUTOPLAY_JS, null)
        topBar?.let { it.bringToFront() }
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
            settings.setSupportMultipleWindows(false) // no ad popups
            setBackgroundColor(0xFF000000.toInt())
            visibility = View.INVISIBLE // hidden until we decide
            webChromeClient = object : WebChromeClient() {
                // Swallow window.open() / target=_blank ad popups.
                override fun onCreateWindow(
                    view: WebView?,
                    isDialog: Boolean,
                    isUserGesture: Boolean,
                    resultMsg: android.os.Message?,
                ): Boolean = false

                // Support the embed's own HTML5 fullscreen button.
                override fun onShowCustomView(view: View?, callback: CustomViewCallback?) {
                    if (view == null) return
                    customViewCallback = callback
                    val container = FrameLayout(this@PlayerActivity).apply {
                        setBackgroundColor(0xFF000000.toInt())
                        layoutParams = FrameLayout.LayoutParams(MATCH, MATCH)
                    }
                    container.addView(view)
                    fullscreenContainer = container
                    root.addView(container)
                    topBar?.bringToFront()
                }

                override fun onHideCustomView() {
                    fullscreenContainer?.let { root.removeView(it) }
                    fullscreenContainer = null
                    customViewCallback?.onCustomViewHidden()
                    customViewCallback = null
                }
            }
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

                // Keep navigation on the embed host; block cross-origin ad jumps.
                override fun shouldOverrideUrlLoading(
                    view: WebView?,
                    request: WebResourceRequest?,
                ): Boolean {
                    val host = request?.url?.host ?: return false
                    val ok = embedHost == null || host.contains("embed.st") ||
                        host.contains("streamed") || host == embedHost
                    return !ok // true = block the navigation
                }

                override fun onPageFinished(view: WebView?, url: String?) {
                    // Nudge autoplay so the playlist is requested promptly.
                    view?.evaluateJavascript(AUTOPLAY_JS, null)
                }
            }
        }
        webView = web
        root.addView(web, 0) // behind the spinner
        web.loadUrl(embedUrl)

        // Fallback: if no playlist is intercepted in time, show the WebView player.
        main.postDelayed({
            if (!nativePlaying && !webFallbackActive) fallbackToWebView()
        }, EXTRACT_TIMEOUT_MS)
    }

    /** Translucent top bar: back, match title, and a Cast button. */
    private fun addTopBar(title: String) {
        val bar = android.widget.LinearLayout(this).apply {
            orientation = android.widget.LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(8), dp(10), dp(12), dp(10))
            background = android.graphics.drawable.GradientDrawable(
                android.graphics.drawable.GradientDrawable.Orientation.TOP_BOTTOM,
                intArrayOf(0xAA000000.toInt(), 0x00000000),
            )
            layoutParams = FrameLayout.LayoutParams(MATCH, WRAP, Gravity.TOP)
            fitsSystemWindows = true
        }
        val back = android.widget.TextView(this).apply {
            text = "✕" // ✕
            setTextColor(0xFFFFFFFF.toInt())
            textSize = 20f
            setPadding(dp(10), dp(4), dp(14), dp(4))
            setOnClickListener { finish() }
        }
        val titleView = android.widget.TextView(this).apply {
            text = title
            setTextColor(0xFFFFFFFF.toInt())
            textSize = 16f
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
            layoutParams = android.widget.LinearLayout.LayoutParams(0, WRAP, 1f)
        }
        bar.addView(back)
        bar.addView(titleView)
        runCatching {
            val themed = android.view.ContextThemeWrapper(this, androidx.mediarouter.R.style.Theme_MediaRouter)
            val cast = androidx.mediarouter.app.MediaRouteButton(themed).apply {
                layoutParams = android.widget.LinearLayout.LayoutParams(dp(40), dp(40))
            }
            com.google.android.gms.cast.framework.CastButtonFactory.setUpMediaRouteButton(applicationContext, cast)
            bar.addView(cast)
        }
        root.addView(bar)
        topBar = bar
    }

    private fun dp(v: Int): Int = (v * resources.displayMetrics.density).toInt()

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
        topBar?.visibility = if (isInPictureInPictureMode) View.GONE else View.VISIBLE
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
        private const val EXTRACT_TIMEOUT_MS = 9_000L
        private const val NATIVE_HEALTH_TIMEOUT_MS = 12_000L
        private const val DESKTOP_UA =
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36"

        /** Unmute + start any <video> and click common play buttons. */
        private const val AUTOPLAY_JS =
            "(function(){try{document.querySelectorAll('video').forEach(function(v){v.muted=false;var p=v.play();if(p&&p.catch)p.catch(function(){});});" +
                "['.play-button','.vjs-big-play-button','.clappr-play-button','[class*=play]'].forEach(function(s){var e=document.querySelector(s);if(e)e.click();});}catch(e){}})();"

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
