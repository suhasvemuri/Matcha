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
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import com.google.android.gms.cast.MediaInfo
import com.google.android.gms.cast.MediaLoadRequestData
import com.google.android.gms.cast.MediaMetadata
import com.google.android.gms.cast.framework.CastContext
import com.google.android.gms.cast.framework.CastSession
import com.google.android.gms.cast.framework.SessionManagerListener

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
    /** True for user-configured IPTV: skip embed-origin header defaults. */
    private var forceNativeMode = false
    private var nativeHealthy = false
    private var extractionDone = false
    private var webFallbackActive = false
    private var embedHost: String? = null
    private val main = Handler(Looper.getMainLooper())

    /** The resolved playable URL (direct or extracted .m3u8) — what we cast. */
    private var castMediaUrl: String? = null
    private val sessionListener = object : SessionManagerListener<CastSession> {
        override fun onSessionStarted(session: CastSession, sessionId: String) = loadRemoteMedia(session)
        override fun onSessionResumed(session: CastSession, wasSuspended: Boolean) = loadRemoteMedia(session)
        override fun onSessionEnded(session: CastSession, error: Int) { exoPlayer?.play() }
        override fun onSessionStarting(session: CastSession) {}
        override fun onSessionStartFailed(session: CastSession, error: Int) {}
        override fun onSessionEnding(session: CastSession) {}
        override fun onSessionResuming(session: CastSession, sessionId: String) {}
        override fun onSessionResumeFailed(session: CastSession, error: Int) {}
        override fun onSessionSuspended(session: CastSession, reason: Int) {}
    }

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

        val forceNative = intent.getBooleanExtra(EXTRA_FORCE_NATIVE, false)
        forceNativeMode = forceNative
        val extraHeaders = intent.getStringArrayListExtra(EXTRA_HEADERS)
            ?.let { flat -> flat.chunked(2).filter { it.size == 2 }.associate { it[0] to it[1] } }
            ?: emptyMap()

        if (forceNative) {
            // A user-configured IPTV stream: trust the URL (the user added it),
            // so allow LAN/HTTP sources a public embed wouldn't get, and play
            // natively with the channel's headers.
            playNative(url, extraHeaders)
        } else if (isDirectStream(url)) {
            if (isSafeMediaUrl(url)) playNative(url, extraHeaders) else finish()
        } else {
            embedHost = runCatching { java.net.URI(url).host }.getOrNull()
            setupEmbedExtraction(url)
        }
    }

    /** Play an HLS/stream URL natively in ExoPlayer. */
    private fun playNative(url: String, headers: Map<String, String>) {
        if (nativePlaying || webFallbackActive) return
        nativePlaying = true
        castMediaUrl = url // now castable
        spinner?.let { root.removeView(it) }

        val httpFactory = DefaultHttpDataSource.Factory()
            .setAllowCrossProtocolRedirects(true)
            .setUserAgent(DESKTOP_UA)
            .setDefaultRequestProperties(
                buildMap {
                    // Embed streams expect an embed.st origin; IPTV streams carry
                    // their own (or none), so only seed that default for embeds.
                    if (!forceNativeMode) {
                        put("Referer", "https://embed.st/")
                        put("Origin", "https://embed.st")
                    }
                    headers.forEach { (k, v) ->
                        if (!k.equals("Accept-Encoding", true) && v.isNotBlank()) put(k, v)
                    }
                    // The stream's CDN gates segments on the WebView's session
                    // cookies (otherwise 503); forward them to ExoPlayer.
                    runCatching { android.webkit.CookieManager.getInstance().getCookie(url) }
                        .getOrNull()?.takeIf { it.isNotBlank() }?.let { put("Cookie", it) }
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
        // Strip the anti-embed nag, reveal the player, and (re)start playback.
        wv.evaluateJavascript(DESHIELD_JS, null)
        wv.evaluateJavascript(AUTOPLAY_JS, null)
        topBar?.let { it.bringToFront() }
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun setupEmbedExtraction(embedUrl: String) {
        val web = WebView(this).apply {
            layoutParams = FrameLayout.LayoutParams(MATCH, MATCH)
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.databaseEnabled = true
            settings.mediaPlaybackRequiresUserGesture = false
            settings.loadWithOverviewMode = true
            settings.useWideViewPort = true
            settings.userAgentString = DESKTOP_UA
            // Present as a full browser: streamed.st's anti-bot shield otherwise
            // mistakes a locked-down WebView for a sandboxed iframe and replaces
            // the player with "Remove sandbox attributes on the iframe tag". So we
            // allow popups (capability present — we just swallow the actual window)
            // and accept cookies/storage like a real browser would.
            settings.setSupportMultipleWindows(true)
            settings.javaScriptCanOpenWindowsAutomatically = true
            // The shield's verification/ad frames are http on an https page; if
            // the browser blocks them as mixed content the shield assumes adblock
            // /sandbox and shows the error. Allow mixed content so it passes.
            settings.mixedContentMode = android.webkit.WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
            val cookies = android.webkit.CookieManager.getInstance()
            cookies.setAcceptCookie(true)
            runCatching { cookies.setAcceptThirdPartyCookies(this, true) }
            setBackgroundColor(0xFF000000.toInt())
            visibility = View.INVISIBLE // hidden until we decide
            // Best-effort un-sandbox of any nested player iframe (harmless if none).
            if (WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
                runCatching {
                    WebViewCompat.addDocumentStartJavaScript(this, UNSANDBOX_JS, setOf("*"))
                }
            }
            webChromeClient = object : WebChromeClient() {
                // window.open() must "succeed" so the shield sees popup capability,
                // but route it to a throwaway WebView so no ad page is shown.
                override fun onCreateWindow(
                    view: WebView?,
                    isDialog: Boolean,
                    isUserGesture: Boolean,
                    resultMsg: android.os.Message?,
                ): Boolean {
                    val transient = WebView(this@PlayerActivity)
                    transient.webViewClient = object : WebViewClient() {
                        override fun shouldOverrideUrlLoading(v: WebView?, r: WebResourceRequest?): Boolean = true
                    }
                    val transport = resultMsg?.obj as? WebView.WebViewTransport ?: return false
                    transport.webView = transient
                    resultMsg.sendToTarget()
                    return true
                }

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

                // Only stop the TOP frame from being yanked to an ad site; let
                // all sub-frames / shield resources load so the player initializes.
                override fun shouldOverrideUrlLoading(
                    view: WebView?,
                    request: WebResourceRequest?,
                ): Boolean {
                    if (request?.isForMainFrame != true) return false
                    val host = request.url?.host ?: return false
                    val ok = embedHost == null || host.contains("embed.st") ||
                        host.contains("streamed") || host == embedHost
                    return !ok // true = block the top-frame navigation
                }

                override fun onPageStarted(view: WebView?, url: String?, favicon: android.graphics.Bitmap?) {
                    // Belt-and-suspenders un-sandbox for WebViews without
                    // DOCUMENT_START_SCRIPT support.
                    view?.evaluateJavascript(UNSANDBOX_JS, null)
                }

                override fun onPageFinished(view: WebView?, url: String?) {
                    view?.evaluateJavascript(UNSANDBOX_JS, null)
                    view?.evaluateJavascript(DESHIELD_JS, null)
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
        val pip = android.widget.TextView(this).apply {
            text = "⧉" // enter Picture-in-Picture
            setTextColor(0xFFFFFFFF.toInt())
            textSize = 19f
            setPadding(dp(10), dp(4), dp(10), dp(4))
            contentDescription = "Picture in picture"
            setOnClickListener { enterPip() }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
        ) {
            bar.addView(pip)
        }
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

    // --- Cast ---------------------------------------------------------------

    /** Hand the current playable stream to the connected Cast device. */
    private fun loadRemoteMedia(session: CastSession) {
        val url = castMediaUrl ?: return
        val rmc = session.remoteMediaClient ?: return
        val meta = MediaMetadata(MediaMetadata.MEDIA_TYPE_MOVIE).apply {
            putString(MediaMetadata.KEY_TITLE, intent.getStringExtra(EXTRA_TITLE) ?: "Live stream")
        }
        val info = MediaInfo.Builder(url)
            .setStreamType(MediaInfo.STREAM_TYPE_LIVE)
            .setContentType("application/x-mpegURL")
            .setMetadata(meta)
            .build()
        val request = MediaLoadRequestData.Builder().setMediaInfo(info).setAutoplay(true).build()
        runCatching { rmc.load(request) }
        exoPlayer?.pause() // local pauses while it plays on the TV
    }

    private fun registerCast() {
        runCatching {
            val cc = CastContext.getSharedInstance(this)
            cc.sessionManager.addSessionManagerListener(sessionListener, CastSession::class.java)
            cc.sessionManager.currentCastSession
                ?.takeIf { it.isConnected }
                ?.let { loadRemoteMedia(it) }
        }
    }

    private fun unregisterCast() {
        runCatching {
            CastContext.getSharedInstance(this).sessionManager
                .removeSessionManagerListener(sessionListener, CastSession::class.java)
        }
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
        registerCast()
    }

    override fun onPause() {
        super.onPause()
        unregisterCast()
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

        /**
         * Strip `sandbox` from every iframe — patches setAttribute before page
         * scripts run (document-start) and observes for late additions — so the
         * embed's nested player iframe isn't sandboxed and will actually play.
         */
        private const val UNSANDBOX_JS =
            "(function(){function strip(n){try{if(n&&n.tagName==='IFRAME')n.removeAttribute('sandbox');" +
                "if(n&&n.querySelectorAll)n.querySelectorAll('iframe[sandbox]').forEach(function(f){f.removeAttribute('sandbox');});}catch(e){}}" +
                "try{var sa=Element.prototype.setAttribute;Element.prototype.setAttribute=function(n,v){" +
                "if(this.tagName==='IFRAME'&&String(n).toLowerCase()==='sandbox')return;return sa.call(this,n,v);};}catch(e){}" +
                "try{new MutationObserver(function(ms){ms.forEach(function(m){if(m.type==='attributes')strip(m.target);" +
                "(m.addedNodes||[]).forEach(strip);});}).observe(document.documentElement||document," +
                "{childList:true,subtree:true,attributes:true,attributeFilter:['sandbox']});}catch(e){}" +
                "try{strip(document);}catch(e){}})();"

        /**
         * Anti-embed shields on these pages overlay a red "Remove sandbox
         * attributes…" nag over the (working) Clappr player. Strip the nag text
         * and force the #player div visible, on an interval so it stays clean.
         */
        private const val DESHIELD_JS =
            "(function(){if(window.__mDesh)return;window.__mDesh=1;var bad=/sandbox|iframe tag|AppleWebKit\\/537/i;" +
                "function clean(){try{if(!document.body)return;" +
                "Array.prototype.slice.call(document.body.childNodes).forEach(function(n){" +
                "if(n.nodeType===3&&bad.test(n.textContent||''))n.parentNode.removeChild(n);});" +
                "document.querySelectorAll('body>*').forEach(function(el){" +
                "if(el.id!=='player'&&el.tagName!=='SCRIPT'&&bad.test(el.textContent||'')&&!el.querySelector('#player,video'))el.remove();});" +
                "document.body.style.color='transparent';" +
                "var p=document.getElementById('player');if(p){p.style.cssText='height:100vh;width:100vw;display:block;visibility:visible';}" +
                "document.querySelectorAll('video').forEach(function(v){v.style.display='block';v.muted=false;var r=v.play&&v.play();if(r&&r.catch)r.catch(function(){});});" +
                "}catch(e){}}setInterval(clean,500);clean();})();"

        /** Unmute + start any <video> and click common play buttons. */
        private const val AUTOPLAY_JS =
            "(function(){try{document.querySelectorAll('video').forEach(function(v){v.muted=false;var p=v.play();if(p&&p.catch)p.catch(function(){});});" +
                "['.play-button','.vjs-big-play-button','.clappr-play-button','[class*=play]'].forEach(function(s){var e=document.querySelector(s);if(e)e.click();});}catch(e){}})();"

        const val EXTRA_URL = "extra_url"
        const val EXTRA_TITLE = "extra_title"
        const val EXTRA_HEADERS = "extra_headers"
        const val EXTRA_FORCE_NATIVE = "extra_force_native"

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

        /**
         * Start the player for a resolved [StreamOption]. IPTV streams are
         * user-configured direct streams: force native ExoPlayer playback and
         * forward the channel's request headers (User-Agent/Referer/…).
         */
        fun start(context: Context, option: com.example.matcha.data.streaming.StreamOption, title: String) {
            val forceNative = option.source == "iptv"
            val intent = Intent(context, PlayerActivity::class.java)
                .putExtra(EXTRA_URL, option.url)
                .putExtra(EXTRA_TITLE, title)
                .putExtra(EXTRA_FORCE_NATIVE, forceNative)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (option.headers.isNotEmpty()) {
                val flat = ArrayList<String>(option.headers.size * 2)
                option.headers.forEach { (k, v) -> flat.add(k); flat.add(v) }
                intent.putStringArrayListExtra(EXTRA_HEADERS, flat)
            }
            context.startActivity(intent)
        }
    }
}
