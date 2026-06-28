package com.example.matcha.ui.detail

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.BiasAlignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.matcha.data.FormationPlayer
import com.example.matcha.data.TeamFormation

private val PitchGreen = Color(0xFF1B7A3D)
private val PitchLine = Color(0x66FFFFFF)

/** Apple Sports-style formation: a pitch with the starting XI laid out, with a
 *  home/away toggle. */
@Composable
fun FormationPitch(home: TeamFormation?, away: TeamFormation?, modifier: Modifier = Modifier) {
    if (home == null && away == null) return
    var showHome by remember { mutableStateOf(home != null) }
    val team = if (showHome) home else away

    Column(modifier.fillMaxWidth()) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            home?.let {
                FilterChip(selected = showHome, onClick = { showHome = true }, label = { Text(it.teamName, maxLines = 1) })
            }
            away?.let {
                FilterChip(selected = !showHome, onClick = { showHome = false }, label = { Text(it.teamName, maxLines = 1) })
            }
        }
        Spacer(Modifier.height(10.dp))
        team?.let { Pitch(it) }
    }
}

@Composable
private fun Pitch(team: TeamFormation) {
    val totalLines = (team.players.maxOfOrNull { it.line } ?: 0) + 1
    Box(
        Modifier.fillMaxWidth().aspectRatio(0.72f).clip(RoundedCornerShape(14.dp)).background(PitchGreen),
    ) {
        Canvas(Modifier.fillMaxSize()) {
            val w = size.width; val h = size.height
            val stroke = 2f
            // outer border
            drawRect(PitchLine, topLeft = Offset(w * 0.04f, h * 0.03f), size = Size(w * 0.92f, h * 0.94f), style = androidx.compose.ui.graphics.drawscope.Stroke(stroke))
            // halfway line
            drawLine(PitchLine, Offset(w * 0.04f, h * 0.5f), Offset(w * 0.96f, h * 0.5f), strokeWidth = stroke)
            // center circle
            drawCircle(PitchLine, radius = w * 0.12f, center = Offset(w * 0.5f, h * 0.5f), style = androidx.compose.ui.graphics.drawscope.Stroke(stroke))
            // penalty boxes (top & bottom)
            drawRect(PitchLine, topLeft = Offset(w * 0.28f, h * 0.03f), size = Size(w * 0.44f, h * 0.12f), style = androidx.compose.ui.graphics.drawscope.Stroke(stroke))
            drawRect(PitchLine, topLeft = Offset(w * 0.28f, h * 0.85f), size = Size(w * 0.44f, h * 0.12f), style = androidx.compose.ui.graphics.drawscope.Stroke(stroke))
        }
        // Players: GK (line 0) at the bottom, forwards near the top.
        team.players.forEach { p ->
            val xBias = ((p.indexInLine + 1f) / (p.lineCount + 1f)) * 2f - 1f
            val yFrac = 0.9f - p.line.toFloat() / (totalLines - 1).coerceAtLeast(1) * 0.8f
            val yBias = yFrac * 2f - 1f
            Box(Modifier.align(BiasAlignment(xBias, yBias))) {
                PlayerDot(p)
            }
        }
    }
}

@Composable
private fun PlayerDot(p: FormationPlayer) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Box(contentAlignment = Alignment.BottomEnd) {
            // Player headshot with a jersey-number circle fallback.
            Box(
                Modifier.size(34.dp).clip(CircleShape)
                    .background(Color.White)
                    .border(2.dp, Color.White, CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                coil.compose.AsyncImage(
                    model = coil.request.ImageRequest.Builder(androidx.compose.ui.platform.LocalContext.current)
                        .data(p.photoUrl).crossfade(true).build(),
                    contentDescription = null,
                    contentScale = androidx.compose.ui.layout.ContentScale.Crop,
                    error = jerseyPainter(p.jersey),
                    fallback = jerseyPainter(p.jersey),
                    placeholder = jerseyPainter(p.jersey),
                    modifier = Modifier.size(34.dp).clip(CircleShape),
                )
            }
            // Jersey number badge
            if (p.jersey.isNotBlank()) {
                Box(
                    Modifier.size(15.dp).clip(CircleShape).background(Color(0xFF0B2C16)),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(p.jersey, color = Color.White, fontSize = 8.sp, fontWeight = FontWeight.Bold, maxLines = 1)
                }
            }
        }
        Spacer(Modifier.height(2.dp))
        Text(
            p.name.substringAfterLast(' ').take(10),
            color = Color.White,
            fontSize = 8.sp,
            fontWeight = FontWeight.Medium,
            textAlign = TextAlign.Center,
            maxLines = 1,
            modifier = Modifier.width(50.dp),
        )
    }
}

@Composable
private fun jerseyPainter(jersey: String): androidx.compose.ui.graphics.painter.Painter =
    androidx.compose.ui.graphics.painter.ColorPainter(Color(0xFFB8C4BC))
