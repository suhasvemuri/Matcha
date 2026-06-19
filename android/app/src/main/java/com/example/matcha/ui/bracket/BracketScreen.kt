package com.example.matcha.ui.bracket

import androidx.compose.foundation.horizontalScroll
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
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.example.matcha.data.BracketMatch
import com.example.matcha.data.BracketRound
import com.example.matcha.data.BracketTeam
import com.example.matcha.data.EspnBracketApi
import com.example.matcha.data.Leagues

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BracketScreen(leagueId: String, onBack: () -> Unit) {
    val league = Leagues.byId(leagueId)
    val rounds by produceState(initialValue = null as List<BracketRound>?, leagueId) {
        value = league?.let { runCatching { EspnBracketApi().fetchBracket(it) }.getOrDefault(emptyList()) }
            ?: emptyList()
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("${league?.displayName ?: "Tournament"} Bracket") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
    ) { padding ->
        val data = rounds
        when {
            data == null -> Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
            data.isEmpty() -> Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                Text(
                    "The knockout bracket isn't set yet.",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            else -> Row(
                Modifier.fillMaxSize().padding(padding).horizontalScroll(rememberScrollState()).padding(12.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                data.forEach { round -> RoundColumn(round) }
            }
        }
    }
}

@Composable
private fun RoundColumn(round: BracketRound) {
    Column(
        Modifier.width(220.dp).verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text(
            round.name.uppercase(),
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.primary,
            modifier = Modifier.padding(bottom = 2.dp),
        )
        round.matches.forEach { BracketMatchCard(it) }
        Spacer(Modifier.height(20.dp))
    }
}

@Composable
private fun BracketMatchCard(match: BracketMatch) {
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainer,
        shape = MaterialTheme.shapes.medium,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(Modifier.padding(10.dp)) {
            BracketTeamRow(match.home, match.decided)
            Spacer(Modifier.height(6.dp))
            BracketTeamRow(match.away, match.decided)
        }
    }
}

@Composable
private fun BracketTeamRow(team: BracketTeam, decided: Boolean) {
    val dim = decided && !team.winner
    val color = if (dim) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.onSurface
    Row(verticalAlignment = Alignment.CenterVertically) {
        AsyncImage(team.logoUrl, null, Modifier.size(20.dp))
        Spacer(Modifier.width(8.dp))
        Text(
            team.name,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = if (team.winner) FontWeight.Bold else FontWeight.Normal,
            color = color,
            maxLines = 1,
            modifier = Modifier.weight(1f),
        )
        team.score?.takeIf { it.isNotBlank() }?.let {
            Text(
                it.substringBefore(" "),
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.Bold,
                color = color,
            )
        }
    }
}
