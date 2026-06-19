package com.example.matcha.ui.common

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import coil.compose.AsyncImage
import coil.request.ImageRequest
import com.example.matcha.R

/**
 * A team crest/flag with a graceful placeholder + error fallback (never a
 * blank gap) and a subtle crossfade.
 */
@Composable
fun Crest(url: String?, modifier: Modifier = Modifier) {
    val placeholder = painterResource(R.drawable.ic_crest_placeholder)
    AsyncImage(
        model = ImageRequest.Builder(LocalContext.current)
            .data(url)
            .crossfade(true)
            .build(),
        contentDescription = null,
        contentScale = ContentScale.Fit,
        placeholder = placeholder,
        error = placeholder,
        fallback = placeholder,
        modifier = modifier,
    )
}
