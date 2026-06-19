package com.example.matcha.ui.main

import android.content.Intent
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.Crossfade
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
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
import com.example.matcha.ui.common.Crest
import com.example.matcha.ui.detail.MatchDetailContent
import com.example.matcha.ui.detail.MatchDetailPlaceholder

/** Favorite team terms (lowercased) for the My-Teams star, avoiding param threading. */
val LocalFavoriteTeams = androidx.compose.runtime.compositionLocalOf { emptySet<String>() }

/** Favorite league ids (for the F1 races section). */
val LocalFavoriteLeagues = androidx.compose.runtime.compositionLocalOf { emptySet<String>() }

@Composable
fun MainScreen(
    onItemClick: (NavKey) -> Unit,
    modifier: Modifier = Modifier,
    viewModel: MainScreenViewModel = viewModel(),
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val sheet by viewModel.streamSheet.collectAsStateWithLifecycle()
    val refreshing by viewModel.isRefreshing.collectAsStateWithLifecycle()
    val favoriteTeams by viewModel.favoriteTeams.collectAsStateWithLifecycle()
    val favoriteLeagues by viewModel.favoriteLeagues.collectAsStateWithLifecycle()
    var selected by rememberSaveable(stateSaver = MatchIdSaver) { mutableStateOf<String?>(null) }

    val selectedMatch = (state as? ScoresUiState.Success)?.groups
        ?.flatMap { it.matches }?.firstOrNull { it.id == selected }

    androidx.compose.runtime.CompositionLocalProvider(
        LocalFavoriteTeams provides favoriteTeams,
        LocalFavoriteLeagues provides favoriteLeagues,
    ) {
    ScoresContent(
        state = state,
        selectedMatch = selectedMatch,
        isRefreshing = refreshing,
        onRefresh = viewModel::refresh,
        onSelect = { selected = it.id },
        onClearSelection = { selected = null },
        onWatch = viewModel::showStreams,
        onOpenFavorites = { onItemClick(com.example.matcha.Favorites) },
        onOpenSettings = { onItemClick(com.example.matcha.Settings) },
        onOpenBracket = { onItemClick(com.example.matcha.Bracket(it)) },
        modifier = modifier,
    )
    sheet?.let {
        StreamSheet(state = it, onDismiss = viewModel::dismissStreams)
    }
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
    isRefreshing: Boolean,
    onRefresh: () -> Unit,
    onSelect: (Match) -> Unit,
    onClearSelection: () -> Unit,
    onWatch: (Match) -> Unit,
    onOpenFavorites: () -> Unit,
    onOpenSettings: () -> Unit,
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
                    onOpenSettings = {
                        haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                        onOpenSettings()
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
                    val hinge = rememberHingeWidthDp()
                    // Equal panes around a real hinge; weighted otherwise.
                    val listWeight = if (hinge > 0.dp) 0.5f else 0.42f
                    Row(Modifier.fillMaxSize()) {
                        Box(Modifier.weight(listWeight).fillMaxSize()) {
                            ScoresPane(displayState, onTap, accent, isRefreshing, onRefresh)
                        }
                        Spacer(Modifier.width(if (hinge > 0.dp) hinge else 14.dp))
                        Surface(
                            color = MaterialTheme.colorScheme.surfaceContainer,
                            shape = MaterialTheme.shapes.extraLarge,
                            modifier = Modifier.weight(1f - listWeight).fillMaxSize(),
                        ) {
                            if (selectedMatch != null) {
                                MatchDetailContent(selectedMatch, onWatch, onOpenBracket = bracketCallback(selectedMatch, onOpenBracket))
                            } else {
                                MatchDetailPlaceholder()
                            }
                        }
                    }
                } else {
                    AnimatedContent(
                        targetState = selectedMatch,
                        transitionSpec = {
                            if (targetState != null) {
                                (slideInHorizontally(initialOffsetX = { it / 4 }) + fadeIn()) togetherWith fadeOut()
                            } else {
                                fadeIn() togetherWith (slideOutHorizontally(targetOffsetX = { it / 4 }) + fadeOut())
                            }
                        },
                        label = "list-detail",
                    ) { detail ->
                        if (detail == null) {
                            ScoresPane(displayState, onTap, accent, isRefreshing, onRefresh)
                        } else {
                            BackHandler(enabled = true, onBack = onClearSelection)
                            MatchDetailContent(detail, onWatch, onOpenBracket = bracketCallback(detail, onOpenBracket), onBack = onClearSelection)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun ScoresHeader(competition: String?, accent: Color, onOpenFavorites: () -> Unit, onOpenSettings: () -> Unit) {
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
                modifier = Modifier.padding(end = 6.dp),
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
        Spacer(Modifier.width(6.dp))
        IconButton(onClick = onOpenSettings) {
            Icon(Icons.Filled.Settings, contentDescription = "Settings", tint = MaterialTheme.colorScheme.onSurfaceVariant)
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

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ScoresPane(
    state: ScoresUiState,
    onTap: (Match) -> Unit,
    accent: Color,
    isRefreshing: Boolean,
    onRefresh: () -> Unit,
) {
    androidx.compose.material3.pulltorefresh.PullToRefreshBox(
        isRefreshing = isRefreshing,
        onRefresh = onRefresh,
        modifier = Modifier.fillMaxSize(),
    ) {
        Crossfade(targetState = state::class, label = "scores") { _ ->
            when (state) {
                ScoresUiState.Loading -> SkeletonList()
                ScoresUiState.Empty -> {
                    if ("FORMULA1" in LocalFavoriteLeagues.current) {
                        LazyColumn(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                            item { F1Section(accent) }
                        }
                    } else CenteredBox {
                        Text(
                            "No matches in your favorites right now.\nPick teams and competitions to follow.",
                            style = MaterialTheme.typography.bodyLarge,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
                is ScoresUiState.Success -> ScoresList(state.groups, onTap, accent)
            }
        }
    }
}

/** Shimmer skeleton placeholder while scores load. */
@Composable
private fun SkeletonList() {
    val transition = rememberInfiniteTransition(label = "shimmer")
    val x by transition.animateFloat(
        initialValue = -500f, targetValue = 1200f,
        animationSpec = infiniteRepeatable(tween(1100), RepeatMode.Restart), label = "x",
    )
    val base = MaterialTheme.colorScheme.surfaceVariant
    val highlight = MaterialTheme.colorScheme.surfaceContainerHigh
    val brush = Brush.linearGradient(
        colors = listOf(base, highlight, base),
        start = androidx.compose.ui.geometry.Offset(x, 0f),
        end = androidx.compose.ui.geometry.Offset(x + 400f, 0f),
    )
    Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Spacer(Modifier.height(8.dp))
        repeat(6) {
            Box(
                Modifier.fillMaxWidth().height(if (it == 0) 96.dp else 64.dp)
                    .clip(MaterialTheme.shapes.large).background(brush),
            )
        }
    }
}

@Composable
private fun ScoresList(groups: List<LeagueMatches>, onWatch: (Match) -> Unit, accent: Color) {
    // Feature the first live match (else the first match overall) as a hero.
    val allMatches = remember(groups) { groups.flatMap { it.matches } }
    val heroId = remember(allMatches) {
        (allMatches.firstOrNull { it.state == MatchState.LIVE } ?: allMatches.firstOrNull())?.id
    }
    LazyColumn(
        verticalArrangement = Arrangement.spacedBy(10.dp),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(bottom = 24.dp),
    ) {
        groups.forEach { group ->
            item(key = "header-${group.league.id}") {
                LeagueHeader(group, accent, Modifier.animateItem())
            }
            items(group.matches, key = { it.id }) { match ->
                if (match.id == heroId) {
                    HeroMatchRow(match, accent, onClick = { onWatch(match) }, modifier = Modifier.animateItem())
                } else {
                    MatchRow(match, accent, onClick = { onWatch(match) }, modifier = Modifier.animateItem())
                }
            }
        }
        item(key = "f1") { F1Section(accent) }
        item(key = "standings") {
            FeedStandings(groups.firstOrNull()?.league, accent)
        }
    }
}

@Composable
private fun F1Section(accent: Color) {
    if ("FORMULA1" !in LocalFavoriteLeagues.current) return
    val races by androidx.compose.runtime.produceState(
        initialValue = emptyList<com.example.matcha.data.RaceEvent>(), Unit,
    ) {
        value = runCatching { com.example.matcha.data.EspnF1Api().fetchRaces() }.getOrDefault(emptyList())
    }
    if (races.isEmpty()) return
    Column(Modifier.fillMaxWidth()) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 18.dp, bottom = 6.dp)) {
            Box(Modifier.size(8.dp).clip(CircleShape).background(accent))
            Spacer(Modifier.width(8.dp))
            Text("FORMULA 1", style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onSurface)
        }
        races.forEach { RaceCard(it) }
    }
}

@Composable
private fun RaceCard(race: com.example.matcha.data.RaceEvent) {
    Surface(
        color = MaterialTheme.colorScheme.surfaceVariant,
        shape = MaterialTheme.shapes.large,
        modifier = Modifier.fillMaxWidth().padding(bottom = 10.dp),
    ) {
        Column(Modifier.fillMaxWidth().padding(16.dp)) {
            Text(race.name, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onSurface, maxLines = 1)
            race.circuit?.let {
                Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
            }
            Text(race.statusDetail, style = MaterialTheme.typography.labelMedium, color = if (race.state == MatchState.LIVE) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(top = 2.dp))
            if (race.results.isNotEmpty()) {
                Spacer(Modifier.height(8.dp))
                race.results.take(3).forEach { d ->
                    Row(Modifier.fillMaxWidth().padding(vertical = 3.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text("P${d.position}", style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.primary, modifier = Modifier.width(34.dp))
                        Text(d.driver, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurface, modifier = Modifier.weight(1f), maxLines = 1)
                        d.team?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1) }
                    }
                }
            }
        }
    }
}

@Composable
private fun FeedStandings(league: com.example.matcha.data.League?, accent: Color) {
    if (league == null || league.espnSport != "soccer") return
    val groups by androidx.compose.runtime.produceState(
        initialValue = emptyList<com.example.matcha.data.StandingGroup>(), league.id,
    ) {
        value = runCatching { com.example.matcha.data.EspnStandingsApi().fetchAll(league) }.getOrDefault(emptyList())
    }
    if (groups.isEmpty()) return
    Column(Modifier.fillMaxWidth()) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 18.dp, bottom = 6.dp)) {
            Box(Modifier.size(8.dp).clip(CircleShape).background(accent))
            Spacer(Modifier.width(8.dp))
            Text("STANDINGS", style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onSurface)
        }
        groups.forEach { g -> StandingsCard(g) }
    }
}

@Composable
private fun StandingsCard(group: com.example.matcha.data.StandingGroup) {
    Surface(
        color = MaterialTheme.colorScheme.surfaceVariant,
        shape = MaterialTheme.shapes.large,
        modifier = Modifier.fillMaxWidth().padding(bottom = 10.dp),
    ) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 10.dp)) {
            Text(group.name, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onSurface, modifier = Modifier.padding(bottom = 6.dp))
            Row(Modifier.fillMaxWidth().padding(bottom = 4.dp)) {
                Text("Team", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.weight(1f))
                listOf("P", "W", "D", "L", "GD", "PTS").forEach {
                    Text(it, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = androidx.compose.ui.text.style.TextAlign.Center, modifier = Modifier.width(if (it == "PTS" || it == "GD") 32.dp else 22.dp))
                }
            }
            group.rows.forEach { r ->
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp)) {
                    Crest(r.logoUrl, Modifier.size(16.dp))
                    Spacer(Modifier.width(7.dp))
                    Text(r.teamName, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurface, maxLines = 1, modifier = Modifier.weight(1f))
                    listOf(r.played.toString(), r.win.toString(), r.draw.toString(), r.loss.toString(), r.goalDiff, r.points.toString()).forEachIndexed { i, v ->
                        Text(v, style = MaterialTheme.typography.bodySmall, fontWeight = if (i == 5) FontWeight.Bold else FontWeight.Normal, color = MaterialTheme.colorScheme.onSurface, textAlign = androidx.compose.ui.text.style.TextAlign.Center, modifier = Modifier.width(if (i >= 4) 32.dp else 22.dp))
                    }
                }
            }
        }
    }
}

/** Subtle frosted-glass card surface with a faint team-color wash. */
private fun Modifier.frostedCard(home: Color, away: Color, shape: androidx.compose.ui.graphics.Shape): Modifier =
    this.clip(shape)
        .background(Brush.horizontalGradient(listOf(home.copy(alpha = 0.16f), away.copy(alpha = 0.16f))))
        .background(Color.White.copy(alpha = 0.06f))
        .border(1.dp, Color.White.copy(alpha = 0.10f), shape)

private fun teamColorOf(team: MatchTeam, fallback: Color): Color =
    team.colorArgb?.let { Color(it) } ?: fallback

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
    val shape = MaterialTheme.shapes.large

    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = modifier.fillMaxWidth()
            .frostedCard(teamColorOf(match.home, accent), teamColorOf(match.away, accent), shape)
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 15.dp),
    ) {
        TeamBadge(match.home, alignStart = true, modifier = Modifier.weight(1f))
        ScoreText(match, match.home, dim = homeDim)
        CenterStatus(match, accent)
        ScoreText(match, match.away, dim = awayDim)
        TeamBadge(match.away, alignStart = false, modifier = Modifier.weight(1f))
    }
}

/** Larger featured card for the top live/next match. */
@Composable
private fun HeroMatchRow(match: Match, accent: Color, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val homeColor = teamColorOf(match.home, accent)
    val awayColor = teamColorOf(match.away, accent)
    val homeScore = leadingScore(match.home.score)
    val awayScore = leadingScore(match.away.score)
    val decided = match.state != MatchState.UPCOMING && homeScore != null && awayScore != null
    val shape = MaterialTheme.shapes.extraLarge

    Column(
        modifier = modifier.fillMaxWidth()
            .clip(shape)
            .background(Brush.horizontalGradient(listOf(homeColor.copy(alpha = 0.42f), awayColor.copy(alpha = 0.42f))))
            .background(Color.Black.copy(alpha = 0.18f))
            .border(1.dp, Color.White.copy(alpha = 0.12f), shape)
            .clickable(onClick = onClick)
            .padding(horizontal = 18.dp, vertical = 18.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
            HeroTeam(match.home, Modifier.weight(1f))
            Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.padding(horizontal = 8.dp)) {
                if (match.state == MatchState.UPCOMING) {
                    Text("vs", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold, color = Color.White)
                } else {
                    Text(
                        "${cleanScore(match.home.score)} – ${cleanScore(match.away.score)}",
                        style = MaterialTheme.typography.displaySmall,
                        fontWeight = FontWeight.ExtraBold,
                        color = Color.White,
                        maxLines = 1,
                    )
                }
                Spacer(Modifier.height(4.dp))
                when (match.state) {
                    MatchState.LIVE -> LiveStatus(match.statusDetail.ifBlank { "LIVE" }, Color.White)
                    MatchState.FINAL -> Text("Final", style = MaterialTheme.typography.labelLarge, color = Color.White.copy(alpha = 0.85f))
                    MatchState.UPCOMING -> Text(kickoffLabel(match.kickoffEpochMs), style = MaterialTheme.typography.labelLarge, color = Color.White.copy(alpha = 0.85f))
                }
            }
            HeroTeam(match.away, Modifier.weight(1f))
        }
        if (decided) Unit
    }
}

@Composable
private fun HeroTeam(team: MatchTeam, modifier: Modifier = Modifier) {
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally) {
        Crest(team.logoUrl, Modifier.size(52.dp))
        Spacer(Modifier.height(8.dp))
        Text(
            team.shortName,
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold,
            color = Color.White,
            maxLines = 1,
            textAlign = androidx.compose.ui.text.style.TextAlign.Center,
        )
    }
}

private fun cleanScore(raw: String?): String =
    raw?.substringBefore(" (")?.trim().orEmpty().ifBlank { "0" }

@Composable
private fun TeamBadge(team: MatchTeam, alignStart: Boolean, modifier: Modifier = Modifier) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = if (alignStart) Arrangement.Start else Arrangement.End,
        modifier = modifier,
    ) {
        val label = team.abbreviation.ifBlank { team.shortName }
        val fav = isFavoriteTeam(team)
        val name = @Composable {
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (!alignStart && fav) { FavStar(); Spacer(Modifier.width(4.dp)) }
                Text(
                    label,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.onSurface,
                    maxLines = 1,
                )
                if (alignStart && fav) { Spacer(Modifier.width(4.dp)); FavStar() }
            }
        }
        val crest = @Composable {
            Crest(team.logoUrl, Modifier.size(38.dp))
        }
        if (alignStart) {
            crest(); Spacer(Modifier.width(12.dp)); name()
        } else {
            name(); Spacer(Modifier.width(12.dp)); crest()
        }
    }
}

@Composable
private fun FavStar() {
    Icon(
        Icons.Filled.Star,
        contentDescription = "Favorite",
        tint = MaterialTheme.colorScheme.primary,
        modifier = Modifier.size(13.dp),
    )
}

@Composable
private fun isFavoriteTeam(team: MatchTeam): Boolean {
    val favs = LocalFavoriteTeams.current
    if (favs.isEmpty()) return false
    val n = team.name.lowercase()
    return favs.any { n.contains(it) || it.contains(n) }
}

@Composable
private fun ScoreText(match: Match, team: MatchTeam, dim: Boolean) {
    if (match.state == MatchState.UPCOMING) {
        Spacer(Modifier.width(8.dp))
        return
    }
    val score = cleanScore(team.score)
    val color = if (dim) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.onSurface
    AnimatedContent(
        targetState = score,
        transitionSpec = {
            (slideInVertically { -it } + fadeIn()) togetherWith (slideOutVertically { it } + fadeOut())
        },
        label = "score",
        modifier = Modifier.padding(horizontal = 12.dp),
    ) { s ->
        Text(
            text = s,
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.ExtraBold,
            maxLines = 1,
            color = color,
        )
    }
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
