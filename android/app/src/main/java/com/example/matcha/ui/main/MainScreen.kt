package com.example.matcha.ui.main

import android.content.Intent
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.net.toUri
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation3.runtime.NavKey
import coil.compose.AsyncImage
import com.example.matcha.data.LeagueMatches
import com.example.matcha.data.Match
import com.example.matcha.data.MatchState
import com.example.matcha.data.MatchTeam
import com.example.matcha.data.streaming.StreamOption
import com.example.matcha.ui.detail.MatchDetailContent
import com.example.matcha.ui.detail.MatchDetailPlaceholder

@Composable
fun MainScreen(
    onItemClick: (NavKey) -> Unit,
    modifier: Modifier = Modifier,
    viewModel: MainScreenViewModel = viewModel(),
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val sheet by viewModel.streamSheet.collectAsStateWithLifecycle()
    var selected by rememberSaveable(stateSaver = MatchIdSaver) { mutableStateOf<String?>(null) }

    val selectedMatch = (state as? ScoresUiState.Success)?.groups
        ?.flatMap { it.matches }?.firstOrNull { it.id == selected }

    ScoresContent(
        state = state,
        selectedMatch = selectedMatch,
        onSelect = { selected = it.id },
        onClearSelection = { selected = null },
        onWatch = viewModel::showStreams,
        onOpenFavorites = { onItemClick(com.example.matcha.Favorites) },
        modifier = modifier,
    )
    sheet?.let {
        StreamSheet(state = it, onDismiss = viewModel::dismissStreams)
    }
}

private val MatchIdSaver = androidx.compose.runtime.saveable.Saver<String?, String>(
    save = { it ?: "" },
    restore = { it.ifEmpty { null } },
)

@Composable
private fun ScoresContent(
    state: ScoresUiState,
    selectedMatch: Match?,
    onSelect: (Match) -> Unit,
    onClearSelection: () -> Unit,
    onWatch: (Match) -> Unit,
    onOpenFavorites: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val haptics = LocalHapticFeedback.current
    BoxWithConstraints(modifier.fillMaxSize()) {
        val twoPane = maxWidth >= 720.dp

        Column(Modifier.fillMaxSize()) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth().padding(bottom = 10.dp),
            ) {
                Text(
                    text = "Matcha",
                    style = MaterialTheme.typography.displaySmall,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.onBackground,
                    modifier = Modifier.weight(1f),
                )
                FilledTonalIconButton(onClick = {
                    haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                    onOpenFavorites()
                }) {
                    Icon(Icons.Filled.Star, contentDescription = "Edit favorites")
                }
            }

            val onTap: (Match) -> Unit = {
                haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                onSelect(it)
            }

            if (twoPane) {
                Row(Modifier.fillMaxSize()) {
                    Box(Modifier.weight(0.42f).fillMaxSize()) {
                        ScoresPane(state, onTap)
                    }
                    Spacer(Modifier.width(12.dp))
                    Surface(
                        color = MaterialTheme.colorScheme.surfaceContainer,
                        shape = MaterialTheme.shapes.large,
                        modifier = Modifier.weight(0.58f).fillMaxSize(),
                    ) {
                        if (selectedMatch != null) {
                            MatchDetailContent(selectedMatch, onWatch)
                        } else {
                            MatchDetailPlaceholder()
                        }
                    }
                }
            } else {
                // Compact: list, or the detail overlaying it when a match is picked.
                AnimatedContent(targetState = selectedMatch, label = "list-detail") { detail ->
                    if (detail == null) {
                        ScoresPane(state, onTap)
                    } else {
                        BackHandler(enabled = true, onBack = onClearSelection)
                        MatchDetailContent(detail, onWatch)
                    }
                }
            }
        }
    }
}

@Composable
private fun ScoresPane(state: ScoresUiState, onTap: (Match) -> Unit) {
    Crossfade(targetState = state::class, label = "scores") { _ ->
        when (state) {
            ScoresUiState.Loading -> CenteredBox { CircularProgressIndicator() }
            ScoresUiState.Empty -> CenteredBox {
                Text(
                    "No matches in your favorites right now.\nPick teams and competitions to follow.",
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            is ScoresUiState.Success -> ScoresList(state.groups, onTap)
        }
    }
}

@Composable
private fun ScoresList(groups: List<LeagueMatches>, onWatch: (Match) -> Unit) {
    LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        groups.forEach { group ->
            item(key = "header-${group.league.id}") {
                LeagueHeader(group, Modifier.animateItem())
            }
            items(group.matches, key = { it.id }) { match ->
                MatchRow(match, onClick = { onWatch(match) }, modifier = Modifier.animateItem())
            }
        }
    }
}

@Composable
private fun LeagueHeader(group: LeagueMatches, modifier: Modifier = Modifier) {
    Text(
        text = group.league.displayName.uppercase(),
        style = MaterialTheme.typography.labelLarge,
        fontWeight = FontWeight.SemiBold,
        color = MaterialTheme.colorScheme.primary,
        modifier = modifier.padding(top = 12.dp, bottom = 2.dp),
    )
}

@Composable
private fun MatchRow(match: Match, onClick: () -> Unit, modifier: Modifier = Modifier) {
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainer,
        shape = MaterialTheme.shapes.large,
        modifier = modifier.fillMaxWidth().clickable(onClick = onClick),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.padding(horizontal = 14.dp, vertical = 12.dp),
        ) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
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
            modifier = Modifier.size(22.dp).clip(CircleShape),
        )
        Spacer(Modifier.width(10.dp))
        Text(
            text = team.name,
            style = MaterialTheme.typography.bodyLarge,
            fontWeight = if (team.isWinner) FontWeight.Bold else FontWeight.Normal,
            color = MaterialTheme.colorScheme.onSurface,
            maxLines = 1,
            modifier = Modifier.weight(1f),
        )
        Text(
            // Cricket scores arrive verbose ("161/5 (18/20 ov, target 156)");
            // show the concise lead ("161/5"). Soccer scores are unaffected.
            text = team.score?.substringBefore(" (")?.trim().orEmpty().ifBlank { "-" },
            style = MaterialTheme.typography.titleMedium,
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
    when (match.state) {
        MatchState.LIVE -> LivePill(match.statusDetail.ifBlank { "LIVE" })
        MatchState.FINAL -> StatusPill("FT", MaterialTheme.colorScheme.surfaceContainerHigh, MaterialTheme.colorScheme.onSurfaceVariant)
        MatchState.UPCOMING -> StatusPill(match.statusDetail.ifBlank { "Soon" }, MaterialTheme.colorScheme.surfaceContainerHigh, MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun StatusPill(label: String, container: Color, content: Color) {
    Surface(color = container, shape = MaterialTheme.shapes.small) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.SemiBold,
            color = content,
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
        )
    }
}

@Composable
private fun LivePill(label: String) {
    val transition = rememberInfiniteTransition(label = "live")
    val pulse by transition.animateFloat(
        initialValue = 0.35f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(700), RepeatMode.Reverse),
        label = "pulse",
    )
    Surface(color = MaterialTheme.colorScheme.errorContainer, shape = MaterialTheme.shapes.small) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
        ) {
            Box(
                Modifier.size(7.dp).clip(CircleShape)
                    .background(MaterialTheme.colorScheme.error.copy(alpha = pulse)),
            )
            Spacer(Modifier.width(5.dp))
            Text(
                text = label,
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onErrorContainer,
            )
        }
    }
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
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onSurface,
            )
            Text(
                text = "${state.match.home.name} vs ${state.match.away.name}",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(bottom = 14.dp),
            )
            when {
                state.loading -> Box(
                    Modifier.fillMaxWidth().padding(24.dp),
                    contentAlignment = Alignment.Center,
                ) { CircularProgressIndicator() }

                state.options.isEmpty() -> Text(
                    "No streams found for this match yet.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(bottom = 16.dp),
                )

                else -> Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    val title = "${state.match.home.name} vs ${state.match.away.name}"
                    state.options.forEach { option ->
                        StreamOptionRow(option) {
                            // Play in the in-app player (WebView for embeds,
                            // ExoPlayer + Cast for direct streams).
                            runCatching {
                                com.example.matcha.player.PlayerActivity.start(context, option.url, title)
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
        shape = MaterialTheme.shapes.medium,
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick),
    ) {
        Text(
            text = option.label,
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Medium,
            color = MaterialTheme.colorScheme.onSecondaryContainer,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 14.dp),
        )
    }
}
