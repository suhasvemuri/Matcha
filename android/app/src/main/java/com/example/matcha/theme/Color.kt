package com.example.matcha.theme

import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.ui.graphics.Color

/** Matcha brand palette — a fresh green seed, tuned for sports scorecards. */

val MatchaLightColors = lightColorScheme(
    primary = Color(0xFF3F6E1F),
    onPrimary = Color(0xFFFFFFFF),
    primaryContainer = Color(0xFFBFF396),
    onPrimaryContainer = Color(0xFF0E2000),
    secondary = Color(0xFF55624C),
    onSecondary = Color(0xFFFFFFFF),
    secondaryContainer = Color(0xFFD9E7CB),
    onSecondaryContainer = Color(0xFF131F0D),
    tertiary = Color(0xFF386666),
    onTertiary = Color(0xFFFFFFFF),
    tertiaryContainer = Color(0xFFBBEBEB),
    onTertiaryContainer = Color(0xFF00201F),
    error = Color(0xFFBA1A1A),
    onError = Color(0xFFFFFFFF),
    errorContainer = Color(0xFFFFDAD6),
    background = Color(0xFFF9FBEF),
    onBackground = Color(0xFF1A1C16),
    surface = Color(0xFFF9FBEF),
    onSurface = Color(0xFF1A1C16),
    surfaceVariant = Color(0xFFE0E4D6),
    onSurfaceVariant = Color(0xFF44483D),
    outline = Color(0xFF74796C),
    surfaceContainer = Color(0xFFEDEFE3),
    surfaceContainerHigh = Color(0xFFE7E9DD),
)

/**
 * Apple Sports-inspired dark scheme: true black canvas, neutral dark cards,
 * Apple-gray secondary text, with a Matcha-green accent for live/branding.
 */
val MatchaDarkColors = darkColorScheme(
    primary = Color(0xFF6FD66F),
    onPrimary = Color(0xFF00390B),
    primaryContainer = Color(0xFF005313),
    onPrimaryContainer = Color(0xFF8FF896),
    secondary = Color(0xFFBDCBB0),
    onSecondary = Color(0xFF283420),
    secondaryContainer = Color(0xFF2C2C2E),
    onSecondaryContainer = Color(0xFFE6E6EA),
    tertiary = Color(0xFF7FD4D4),
    onTertiary = Color(0xFF003737),
    tertiaryContainer = Color(0xFF1E4E4E),
    onTertiaryContainer = Color(0xFFBBEBEB),
    error = Color(0xFFFF6B6B),
    onError = Color(0xFF000000),
    errorContainer = Color(0xFF3A0E0E),
    onErrorContainer = Color(0xFFFFB4AB),
    // Clean neutral-dark base — the per-competition gradient supplies the color.
    background = Color(0xFF070809),
    onBackground = Color(0xFFFFFFFF),
    surface = Color(0xFF070809),
    onSurface = Color(0xFFF5F6F7),
    // Cards: a clean, slightly translucent-feeling elevated surface.
    surfaceVariant = Color(0xFF191B1F),
    onSurfaceVariant = Color(0xFF9BA1A8), // neutral Apple-gray secondary
    outline = Color(0xFF34373D),
    surfaceContainerLowest = Color(0xFF050608),
    surfaceContainerLow = Color(0xFF121418),
    surfaceContainer = Color(0xFF191B1F),
    surfaceContainerHigh = Color(0xFF24272D),
    surfaceContainerHighest = Color(0xFF30343B),
)

/** Default gradient (brand green); overridden per-competition at runtime. */
val MatchaGradientTop = Color(0xFF0E3A22)
val MatchaGradientBottom = Color(0xFF05070A)
