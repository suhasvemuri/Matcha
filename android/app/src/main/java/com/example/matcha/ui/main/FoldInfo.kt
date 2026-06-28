package com.example.matcha.ui.main

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.window.layout.FoldingFeature
import androidx.window.layout.WindowInfoTracker

/**
 * Width of a separating vertical fold (book/tabletop posture), in dp, or 0 if
 * there's no such hinge. Used to align the two-pane layout to the hinge.
 */
@Composable
fun rememberHingeWidthDp(): Dp {
    val activity = LocalContext.current.findActivity() ?: return 0.dp
    val flow = remember(activity) {
        WindowInfoTracker.getOrCreate(activity).windowLayoutInfo(activity)
    }
    val layoutInfo by flow.collectAsState(initial = null)
    val density = LocalDensity.current

    val fold = layoutInfo?.displayFeatures
        ?.filterIsInstance<FoldingFeature>()
        ?.firstOrNull { it.orientation == FoldingFeature.Orientation.VERTICAL && it.isSeparating }
    return fold?.let { with(density) { it.bounds.width().toDp() } } ?: 0.dp
}

private fun Context.findActivity(): Activity? {
    var ctx: Context? = this
    while (ctx is ContextWrapper) {
        if (ctx is Activity) return ctx
        ctx = ctx.baseContext
    }
    return null
}
