package com.example.matcha.ui.main

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
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation3.runtime.NavKey
import coil.compose.AsyncImage
import com.example.matcha.data.LeagueMatches
import com.example.matcha.data.Match
import com.example.matcha.data.MatchState
import com.example.matcha.data.MatchTeam

@Composable
fun MainScreen(
    onItemClick: (NavKey) -> Unit,
    modifier: Modifier = Modifier,
    viewModel: MainScreenViewModel = viewModel(),
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    ScoresContent(state = state, modifier = modifier)
}

@Composable
private fun ScoresContent(state: ScoresUiState, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxSize()) {
        Text(
            text = "Matcha",
            fontSize = 30.sp,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.onBackground,
            modifier = Modifier.padding(bottom = 8.dp),
        )
        when (state) {
            ScoresUiState.Loading -> CenteredBox { CircularProgressIndicator() }
            ScoresUiState.Empty -> CenteredBox {
                Text(
                    "No matches in your favorites right now.\nPick teams and competitions to follow.",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            is ScoresUiState.Success -> ScoresList(state.groups)
        }
    }
}

@Composable
private fun ScoresList(groups: List<LeagueMatches>) {
    LazyColumn(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        groups.forEach { group ->
            item(key = "header-${group.league.id}") {
                LeagueHeader(group)
            }
            items(group.matches, key = { it.id }) { match ->
                MatchRow(match)
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
private fun MatchRow(match: Match) {
    Surface(
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.4f),
        shape = RoundedCornerShape(12.dp),
        modifier = Modifier.fillMaxWidth(),
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
            text = team.score ?: "-",
            fontSize = 15.sp,
            fontWeight = FontWeight.Bold,
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
