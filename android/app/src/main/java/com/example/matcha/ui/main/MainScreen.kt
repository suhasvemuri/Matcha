package com.example.matcha.ui.main

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.net.toUri
import android.content.Intent
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation3.runtime.NavKey
import coil.compose.AsyncImage
import com.example.matcha.data.LeagueMatches
import com.example.matcha.data.Match
import com.example.matcha.data.MatchState
import com.example.matcha.data.MatchTeam
import com.example.matcha.data.streaming.StreamOption

@Composable
fun MainScreen(
    onItemClick: (NavKey) -> Unit,
    modifier: Modifier = Modifier,
    viewModel: MainScreenViewModel = viewModel(),
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val sheet by viewModel.streamSheet.collectAsStateWithLifecycle()
    ScoresContent(
        state = state,
        onWatch = viewModel::showStreams,
        onOpenFavorites = { onItemClick(com.example.matcha.Favorites) },
        modifier = modifier,
    )
    sheet?.let {
        StreamSheet(state = it, onDismiss = viewModel::dismissStreams)
    }
}

@Composable
private fun ScoresContent(
    state: ScoresUiState,
    onWatch: (Match) -> Unit,
    onOpenFavorites: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier.fillMaxSize()) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.fillMaxWidth().padding(bottom = 8.dp),
        ) {
            Text(
                text = "Matcha",
                fontSize = 30.sp,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onBackground,
                modifier = Modifier.weight(1f),
            )
            IconButton(onClick = onOpenFavorites) {
                Icon(Icons.Filled.Star, contentDescription = "Edit favorites")
            }
        }
        when (state) {
            ScoresUiState.Loading -> CenteredBox { CircularProgressIndicator() }
            ScoresUiState.Empty -> CenteredBox {
                Text(
                    "No matches in your favorites right now.\nPick teams and competitions to follow.",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            is ScoresUiState.Success -> ScoresList(state.groups, onWatch)
        }
    }
}

@Composable
private fun ScoresList(groups: List<LeagueMatches>, onWatch: (Match) -> Unit) {
    LazyColumn(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        groups.forEach { group ->
            item(key = "header-${group.league.id}") {
                LeagueHeader(group)
            }
            items(group.matches, key = { it.id }) { match ->
                MatchRow(match, onClick = { onWatch(match) })
            }
        }
    }
}

@Composable
private fun LeagueHeader(group: LeagueMatches) {
    Text(
        text = group.league.displayName.uppercase(),
        fontSize = 12.sp,
        fontWeight = FontWeight.SemiBold,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(top = 10.dp, bottom = 2.dp),
    )
}

@Composable
private fun MatchRow(match: Match, onClick: () -> Unit) {
    Surface(
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.4f),
        shape = RoundedCornerShape(12.dp),
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
        ) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                TeamLine(match.home, match.state)
                TeamLine(match.away, match.state)
            }
            Spacer(Modifier.width(10.dp))
            StatusBadge(match)
        }
    }
}

@Composable
private fun TeamLine(team: MatchTeam, state: MatchState) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        AsyncImage(
            model = team.logoUrl,
            contentDescription = null,
            contentScale = ContentScale.Fit,
            modifier = Modifier.size(20.dp).clip(CircleShape),
        )
        Spacer(Modifier.width(8.dp))
        Text(
            text = team.name,
            fontSize = 15.sp,
            fontWeight = if (team.isWinner) FontWeight.Bold else FontWeight.Normal,
            color = MaterialTheme.colorScheme.onSurface,
            modifier = Modifier.weight(1f),
        )
        Text(
            // Cricket scores arrive verbose ("161/5 (18/20 ov, target 156)");
            // show the concise lead ("161/5"). Soccer scores are unaffected.
            text = team.score?.substringBefore(" (")?.trim().orEmpty().ifBlank { "-" },
            fontSize = 15.sp,
            fontWeight = FontWeight.Bold,
            maxLines = 1,
            color = if (state == MatchState.UPCOMING)
                MaterialTheme.colorScheme.onSurfaceVariant
            else MaterialTheme.colorScheme.onSurface,
        )
    }
}

@Composable
private fun StatusBadge(match: Match) {
    val (label, color) = when (match.state) {
        MatchState.LIVE -> (match.statusDetail.ifBlank { "LIVE" }) to MaterialTheme.colorScheme.error
        MatchState.FINAL -> "FT" to MaterialTheme.colorScheme.onSurfaceVariant
        MatchState.UPCOMING -> match.statusDetail.ifBlank { "Soon" } to MaterialTheme.colorScheme.onSurfaceVariant
    }
    Text(
        text = label,
        fontSize = 11.sp,
        fontWeight = FontWeight.SemiBold,
        color = color,
        modifier = Modifier.width(64.dp),
    )
}

@Composable
private fun CenteredBox(content: @Composable () -> Unit) {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { content() }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun StreamSheet(state: StreamSheetState, onDismiss: () -> Unit) {
    val context = LocalContext.current
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 12.dp)) {
            Text(
                text = "Where to watch",
                fontSize = 18.sp,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onSurface,
            )
            Text(
                text = "${state.match.home.name} vs ${state.match.away.name}",
                fontSize = 13.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(bottom = 12.dp),
            )
            when {
                state.loading -> Box(
                    Modifier.fillMaxWidth().padding(24.dp),
                    contentAlignment = Alignment.Center,
                ) { CircularProgressIndicator() }

                state.options.isEmpty() -> Text(
                    "No streams found for this match yet.",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(bottom = 16.dp),
                )

                else -> Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    state.options.forEach { option ->
                        StreamOptionRow(option) {
                            runCatching {
                                context.startActivity(
                                    Intent(Intent.ACTION_VIEW, option.url.toUri())
                                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                                )
                            }
                        }
                    }
                    Spacer(Modifier.size(16.dp))
                }
            }
        }
    }
}

@Composable
private fun StreamOptionRow(option: StreamOption, onClick: () -> Unit) {
    Surface(
        color = MaterialTheme.colorScheme.secondaryContainer,
        shape = RoundedCornerShape(10.dp),
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick),
    ) {
        Text(
            text = option.label,
            fontSize = 15.sp,
            fontWeight = FontWeight.Medium,
            color = MaterialTheme.colorScheme.onSecondaryContainer,
            modifier = Modifier.padding(horizontal = 14.dp, vertical = 12.dp),
        )
    }
}
