package com.example.matcha.ui.detail

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.example.matcha.data.EspnDetailApi
import com.example.matcha.data.Match
import com.example.matcha.data.MatchExtras
import com.example.matcha.data.MatchState
import com.example.matcha.data.MatchTeam
import com.example.matcha.data.StandingGroup
import com.example.matcha.data.StandingRow
import com.example.matcha.data.StatComparison
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Rich match detail: large crests, scoreline, live/scheduled status, league,
 * venue, and kickoff. Used both as a full screen (compact) and as the detail
 * pane on wide/unfolded layouts. [onWatch] opens the where-to-watch sheet.
 */
@Composable
fun MatchDetailContent(
    match: Match,
    onWatch: (Match) -> Unit,
    modifier: Modifier = Modifier,
    onOpenBracket: ((String) -> Unit)? = null,
) {
    val extras by produceState(initialValue = MatchExtras(), match.id) {
        value = runCatching { EspnDetailApi().fetch(match) }.getOrDefault(MatchExtras())
    }
    Column(
        modifier = modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            text = match.leagueName.uppercase(),
            style = MaterialTheme.typography.labelLarge,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.primary,
        )
        Spacer(Modifier.height(4.dp))
        StatusLine(match)
        Spacer(Modifier.height(24.dp))

        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
            TeamCrest(match.home, Modifier.weight(1f))
            ScoreBlock(match)
            TeamCrest(match.away, Modifier.weight(1f))
        }

        Spacer(Modifier.height(24.dp))
        Button(onClick = { onWatch(match) }, modifier = Modifier.fillMaxWidth()) {
            Icon(Icons.Filled.PlayArrow, contentDescription = null)
            Spacer(Modifier.size(8.dp))
            Text("Where to watch")
        }
        onOpenBracket?.let { open ->
            Spacer(Modifier.height(10.dp))
            androidx.compose.material3.OutlinedButton(
                onClick = { open(match.leagueId) },
                modifier = Modifier.fillMaxWidth(),
            ) { Text("Tournament bracket") }
        }

        if (extras.stats.isNotEmpty()) {
            SectionHeader("Team Stats")
            extras.stats.forEach { StatBar(it) }
        }

        if (extras.homeFormation != null || extras.awayFormation != null) {
            SectionHeader("Lineups")
            FormationPitch(extras.homeFormation, extras.awayFormation)
        }

        extras.group?.let { group ->
            SectionHeader(group.name)
            StandingsTable(group)
        }

        SectionHeader("Match Info")
        match.broadcast?.takeIf { it.isNotBlank() }?.let { InfoRow("Watch on", it) }
        match.venue?.takeIf { it.isNotBlank() }?.let { InfoRow("Venue", it) }
        InfoRow("Kickoff", formatKickoff(match.kickoffEpochMs))
        InfoRow("Competition", match.leagueName)
        Spacer(Modifier.height(16.dp))
    }
}

@Composable
private fun SectionHeader(title: String) {
    Text(
        text = title.uppercase(),
        style = MaterialTheme.typography.labelMedium,
        fontWeight = FontWeight.SemiBold,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.fillMaxWidth().padding(top = 24.dp, bottom = 10.dp),
    )
}

@Composable
private fun StatBar(stat: StatComparison) {
    Column(Modifier.fillMaxWidth().padding(vertical = 6.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(stat.home, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onSurface)
            Text(
                stat.label,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
                modifier = Modifier.weight(1f),
            )
            Text(stat.away, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onSurface)
        }
        Spacer(Modifier.height(5.dp))
        val frac = stat.homeFraction.coerceIn(0.04f, 0.96f)
        Row(
            Modifier.fillMaxWidth().height(6.dp).clip(RoundedCornerShape(3.dp)),
        ) {
            Box(Modifier.weight(frac).fillMaxSize().background(MaterialTheme.colorScheme.primary))
            Spacer(Modifier.width(2.dp))
            Box(Modifier.weight(1f - frac).fillMaxSize().background(MaterialTheme.colorScheme.surfaceContainerHighest))
        }
    }
}

@Composable
private fun StandingsTable(group: StandingGroup) {
    Column(Modifier.fillMaxWidth()) {
        Row(Modifier.fillMaxWidth().padding(vertical = 4.dp)) {
            Text("Team", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.weight(1f))
            listOf("P", "W", "D", "L", "GD", "PTS").forEach {
                Text(it, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center, modifier = Modifier.width(if (it == "PTS" || it == "GD") 34.dp else 24.dp))
            }
        }
        group.rows.forEach { StandingRowView(it) }
    }
}

@Composable
private fun StandingRowView(row: StandingRow) {
    val bg = if (row.highlight) MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.35f) else Color.Transparent
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(8.dp)).background(bg).padding(vertical = 7.dp, horizontal = 4.dp),
    ) {
        AsyncImage(row.logoUrl, null, Modifier.size(18.dp), contentScale = ContentScale.Fit)
        Spacer(Modifier.width(8.dp))
        Text(row.teamName, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurface, maxLines = 1, modifier = Modifier.weight(1f))
        Cell(row.played.toString(), 24.dp)
        Cell(row.win.toString(), 24.dp)
        Cell(row.draw.toString(), 24.dp)
        Cell(row.loss.toString(), 24.dp)
        Cell(row.goalDiff, 34.dp)
        Cell(row.points.toString(), 34.dp, bold = true)
    }
}

@Composable
private fun Cell(text: String, width: androidx.compose.ui.unit.Dp, bold: Boolean = false) {
    Text(
        text = text,
        style = MaterialTheme.typography.bodySmall,
        fontWeight = if (bold) FontWeight.Bold else FontWeight.Normal,
        color = MaterialTheme.colorScheme.onSurface,
        textAlign = TextAlign.Center,
        modifier = Modifier.width(width),
    )
}

@Composable
private fun StatusLine(match: Match) {
    val (label, color) = when (match.state) {
        MatchState.LIVE -> match.statusDetail.ifBlank { "LIVE" } to MaterialTheme.colorScheme.error
        MatchState.FINAL -> "Full time" to MaterialTheme.colorScheme.onSurfaceVariant
        MatchState.UPCOMING -> match.statusDetail.ifBlank { "Upcoming" } to MaterialTheme.colorScheme.onSurfaceVariant
    }
    Text(label, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, color = color)
}

@Composable
private fun TeamCrest(team: MatchTeam, modifier: Modifier = Modifier) {
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally) {
        AsyncImage(
            model = team.logoUrl,
            contentDescription = null,
            contentScale = ContentScale.Fit,
            modifier = Modifier.size(64.dp).clip(CircleShape),
        )
        Spacer(Modifier.height(8.dp))
        Text(
            text = team.name,
            style = MaterialTheme.typography.titleSmall,
            fontWeight = if (team.isWinner) FontWeight.Bold else FontWeight.Medium,
            textAlign = TextAlign.Center,
            color = MaterialTheme.colorScheme.onSurface,
        )
        team.record?.takeIf { it.isNotBlank() }?.let {
            Text(
                text = it,
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        team.form?.takeIf { it.isNotBlank() }?.let {
            Text(
                text = it.takeLast(5),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.primary,
            )
        }
    }
}

@Composable
private fun ScoreBlock(match: Match) {
    val text = if (match.state == MatchState.UPCOMING) "vs" else
        "${score(match.home)} – ${score(match.away)}"
    Text(
        text = text,
        style = MaterialTheme.typography.headlineMedium,
        fontWeight = FontWeight.Bold,
        color = MaterialTheme.colorScheme.onSurface,
        modifier = Modifier.padding(horizontal = 12.dp),
    )
}

@Composable
private fun InfoRow(label: String, value: String) {
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainer,
        shape = MaterialTheme.shapes.medium,
        modifier = Modifier.fillMaxWidth().padding(vertical = 3.dp),
    ) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp)) {
            Text(label, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.weight(1f))
            Text(value, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium, color = MaterialTheme.colorScheme.onSurface)
        }
    }
}

@Composable
fun MatchDetailPlaceholder(modifier: Modifier = Modifier) {
    Box(modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Text(
            "Select a match to see details",
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

private fun score(team: MatchTeam): String =
    team.score?.substringBefore(" (")?.trim().orEmpty().ifBlank { "0" }

private fun formatKickoff(epochMs: Long): String {
    if (epochMs <= 0) return "TBD"
    val fmt = SimpleDateFormat("EEE d MMM, h:mm a", Locale.getDefault())
    return fmt.format(Date(epochMs))
}
