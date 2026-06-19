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
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.widthIn
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
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
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
import com.example.matcha.theme.CompetitionThemes
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
        onOpenBracket = { onItemClick(com.example.matcha.Bracket(it)) },
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
    onOpenBracket: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val haptics = LocalHapticFeedback.current
    var tab by rememberSaveable { mutableStateOf(DateTab.TODAY) }
    val displayState = remember(state, tab) { filterByDate(state, tab) }

    // Theme the canvas by the dominant competition on screen (Apple Sports style).
    val dominant = (displayState as? ScoresUiState.Success)?.groups?.firstOrNull()
    val theme = CompetitionThemes.forLeague(dominant?.league?.id)
    val accent = theme.accent

    Box(
        modifier.fillMaxSize().background(
            Brush.verticalGradient(
                0f to theme.gradientTop,
                0.42f to theme.gradientBottom,
                1f to MaterialTheme.colorScheme.background,
            ),
        ),
    ) {
        BoxWithConstraints(Modifier.fillMaxSize().safeDrawingPadding().padding(horizontal = 18.dp)) {
            val twoPane = maxWidth >= 720.dp

            Column(Modifier.fillMaxSize()) {
                ScoresHeader(
                    competition = dominant?.league?.displayName,
                    accent = accent,
                    onOpenFavorites = {
                        haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                        onOpenFavorites()
                    },
                )

                DateTabRow(selected = tab, accent = accent, onSelect = {
                    haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                    tab = it
                })

                val onTap: (Match) -> Unit = {
                    haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                    onSelect(it)
                }

                if (twoPane) {
                    Row(Modifier.fillMaxSize()) {
                        Box(Modifier.weight(0.42f).fillMaxSize()) {
                            ScoresPane(displayState, onTap, accent)
                        }
                        Spacer(Modifier.width(14.dp))
                        Surface(
                            color = MaterialTheme.colorScheme.surfaceContainer,
                            shape = MaterialTheme.shapes.extraLarge,
                            modifier = Modifier.weight(0.58f).fillMaxSize(),
                        ) {
                            if (selectedMatch != null) {
                                MatchDetailContent(selectedMatch, onWatch, onOpenBracket = bracketCallback(selectedMatch, onOpenBracket))
                            } else {
                                MatchDetailPlaceholder()
                            }
                        }
                    }
                } else {
                    AnimatedContent(targetState = selectedMatch, label = "list-detail") { detail ->
                        if (detail == null) {
                            ScoresPane(displayState, onTap, accent)
                        } else {
                            BackHandler(enabled = true, onBack = onClearSelection)
                            MatchDetailContent(detail, onWatch, onOpenBracket = bracketCallback(detail, onOpenBracket))
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun ScoresHeader(competition: String?, accent: Color, onOpenFavorites: () -> Unit) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.fillMaxWidth().padding(top = 6.dp, bottom = 12.dp),
    ) {
        Text(
            text = "Matcha",
            style = MaterialTheme.typography.headlineLarge,
            fontWeight = FontWeight.ExtraBold,
            color = MaterialTheme.colorScheme.onBackground,
        )
        Spacer(Modifier.weight(1f))
        competition?.let {
            Surface(
                color = accent.copy(alpha = 0.18f),
                shape = MaterialTheme.shapes.extraLarge,
                modifier = Modifier.padding(end = 8.dp),
            ) {
                Text(
                    it,
                    style = MaterialTheme.typography.labelLarge,
                    fontWeight = FontWeight.SemiBold,
                    color = accent,
                    maxLines = 1,
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
                )
            }
        }
        FilledTonalIconButton(onClick = onOpenFavorites) {
            Icon(Icons.Filled.Star, contentDescription = "Edit favorites")
        }
    }
}

enum class DateTab(val label: String) { YESTERDAY("Yesterday"), TODAY("Today"), UPCOMING("Upcoming") }

/** Cup competitions that have a knockout bracket. */
private val BRACKET_LEAGUES = setOf("FFWC", "FFWWC", "UEFA", "EUEFA")

private fun bracketCallback(match: Match, onOpenBracket: (String) -> Unit): ((String) -> Unit)? =
    if (match.leagueId in BRACKET_LEAGUES) onOpenBracket else null

@Composable
private fun DateTabRow(selected: DateTab, accent: Color, onSelect: (DateTab) -> Unit) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(22.dp),
        modifier = Modifier.fillMaxWidth().padding(bottom = 14.dp),
    ) {
        DateTab.entries.forEach { t ->
            val active = t == selected
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(
                    text = t.label,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = if (active) FontWeight.Bold else FontWeight.Medium,
                    color = if (active) MaterialTheme.colorScheme.onSurface
                    else MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.clickable { onSelect(t) },
                )
                Spacer(Modifier.height(4.dp))
                Box(
                    Modifier.height(3.dp).width(if (active) 20.dp else 0.dp)
                        .clip(CircleShape).background(accent),
                )
            }
        }
    }
}

/** Bucket matches by kickoff date relative to today (device timezone). */
private fun filterByDate(state: ScoresUiState, tab: DateTab): ScoresUiState {
    if (state !is ScoresUiState.Success) return state
    val cal = java.util.Calendar.getInstance().apply {
        set(java.util.Calendar.HOUR_OF_DAY, 0); set(java.util.Calendar.MINUTE, 0)
        set(java.util.Calendar.SECOND, 0); set(java.util.Calendar.MILLISECOND, 0)
    }
    val todayStart = cal.timeInMillis
    val tomorrowStart = todayStart + 24L * 60 * 60 * 1000

    fun bucket(m: Match): DateTab = when {
        m.kickoffEpochMs <= 0 -> DateTab.TODAY
        m.kickoffEpochMs < todayStart -> DateTab.YESTERDAY
        m.kickoffEpochMs < tomorrowStart -> DateTab.TODAY
        else -> DateTab.UPCOMING
    }

    val filtered = state.groups
        .map { g -> g.copy(matches = g.matches.filter { bucket(it) == tab }) }
        .filter { it.matches.isNotEmpty() }
    return if (filtered.isEmpty()) ScoresUiState.Empty else ScoresUiState.Success(filtered)
}

@Composable
private fun ScoresPane(state: ScoresUiState, onTap: (Match) -> Unit, accent: Color) {
    Crossfade(targetState = state::class, label = "scores") { _ ->
        when (state) {
            ScoresUiState.Loading -> CenteredBox { CircularProgressIndicator(color = accent) }
            ScoresUiState.Empty -> CenteredBox {
                Text(
                    "No matches in your favorites right now.\nPick teams and competitions to follow.",
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            is ScoresUiState.Success -> ScoresList(state.groups, onTap, accent)
        }
    }
}

@Composable
private fun ScoresList(groups: List<LeagueMatches>, onWatch: (Match) -> Unit, accent: Color) {
    LazyColumn(
        verticalArrangement = Arrangement.spacedBy(10.dp),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(bottom = 24.dp),
    ) {
        groups.forEach { group ->
            item(key = "header-${group.league.id}") {
                LeagueHeader(group, accent, Modifier.animateItem())
            }
            items(group.matches, key = { it.id }) { match ->
                MatchRow(match, accent, onClick = { onWatch(match) }, modifier = Modifier.animateItem())
            }
        }
    }
}

@Composable
private fun LeagueHeader(group: LeagueMatches, accent: Color, modifier: Modifier = Modifier) {
    Row(verticalAlignment = Alignment.CenterVertically, modifier = modifier.padding(top = 16.dp, bottom = 6.dp)) {
        Box(Modifier.size(8.dp).clip(CircleShape).background(accent))
        Spacer(Modifier.width(8.dp))
        Text(
            text = group.league.displayName.uppercase(),
            style = MaterialTheme.typography.labelLarge,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.onSurface,
        )
    }
}

@Composable
private fun MatchRow(match: Match, accent: Color, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val homeScore = leadingScore(match.home.score)
    val awayScore = leadingScore(match.away.score)
    val decided = match.state != MatchState.UPCOMING && homeScore != null && awayScore != null
    val homeDim = decided && homeScore!! < awayScore!!
    val awayDim = decided && awayScore!! < homeScore!!

    Surface(
        color = MaterialTheme.colorScheme.surfaceVariant,
        shape = MaterialTheme.shapes.large,
        modifier = modifier.fillMaxWidth().clickable(onClick = onClick),
    ) {
        // Apple Sports horizontal card: crest+abbr | score | center status | score | abbr+crest
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 16.dp),
        ) {
            TeamBadge(match.home, alignStart = true, modifier = Modifier.weight(1f))
            ScoreText(match, match.home, dim = homeDim)
            CenterStatus(match, accent)
            ScoreText(match, match.away, dim = awayDim)
            TeamBadge(match.away, alignStart = false, modifier = Modifier.weight(1f))
        }
    }
}

@Composable
private fun TeamBadge(team: MatchTeam, alignStart: Boolean, modifier: Modifier = Modifier) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = if (alignStart) Arrangement.Start else Arrangement.End,
        modifier = modifier,
    ) {
        val label = team.abbreviation.ifBlank { team.shortName }
        val name = @Composable {
            Text(
                label,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onSurface,
                maxLines = 1,
            )
        }
        val crest = @Composable {
            AsyncImage(team.logoUrl, null, Modifier.size(38.dp), contentScale = ContentScale.Fit)
        }
        if (alignStart) {
            crest(); Spacer(Modifier.width(12.dp)); name()
        } else {
            name(); Spacer(Modifier.width(12.dp)); crest()
        }
    }
}

@Composable
private fun ScoreText(match: Match, team: MatchTeam, dim: Boolean) {
    if (match.state == MatchState.UPCOMING) {
        Spacer(Modifier.width(8.dp))
        return
    }
    Text(
        text = team.score?.substringBefore(" (")?.trim().orEmpty().ifBlank { "0" },
        style = MaterialTheme.typography.headlineMedium,
        fontWeight = FontWeight.ExtraBold,
        maxLines = 1,
        color = if (dim) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.onSurface,
        modifier = Modifier.padding(horizontal = 12.dp),
    )
}

@Composable
private fun CenterStatus(match: Match, accent: Color) {
    Box(Modifier.widthIn(min = 58.dp), contentAlignment = Alignment.Center) {
        when (match.state) {
            MatchState.LIVE -> LiveStatus(match.statusDetail.ifBlank { "LIVE" }, accent)
            MatchState.FINAL -> Text(
                "Final",
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                maxLines = 1,
            )
            MatchState.UPCOMING -> Text(
                kickoffLabel(match.kickoffEpochMs).ifBlank { match.statusDetail.ifBlank { "—" } },
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.Medium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                maxLines = 1,
            )
        }
    }
}

@Composable
private fun LiveStatus(label: String, accent: Color) {
    val transition = rememberInfiniteTransition(label = "live")
    val pulse by transition.animateFloat(
        initialValue = 0.4f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(800), RepeatMode.Reverse),
        label = "pulse",
    )
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Box(Modifier.size(7.dp).clip(CircleShape).background(accent.copy(alpha = pulse)))
        Spacer(Modifier.height(3.dp))
        Text(
            text = label,
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.Bold,
            color = accent,
            maxLines = 1,
        )
    }
}

/** Parse the leading integer of a score ("161/5" -> 161, "2" -> 2). */
private fun leadingScore(raw: String?): Int? =
    raw?.trim()?.takeWhile { it.isDigit() }?.toIntOrNull()

private fun kickoffLabel(epochMs: Long): String {
    if (epochMs <= 0) return ""
    val fmt = java.text.SimpleDateFormat("h:mm a", java.util.Locale.getDefault())
    return fmt.format(java.util.Date(epochMs))
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
