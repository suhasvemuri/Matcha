package com.example.matcha.wear.presentation

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.items
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.material.Card
import androidx.wear.compose.material.CircularProgressIndicator
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Text
import androidx.wear.compose.material.TimeText
import com.example.matcha.wear.data.WearMatch
import com.example.matcha.wear.data.WearMatchState
import com.example.matcha.wear.data.WearScoresApi
import kotlinx.coroutines.launch
import androidx.compose.runtime.rememberCoroutineScope

class WearMainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { WearApp() }
    }
}

@Composable
private fun WearApp() {
    val api = remember { WearScoresApi() }
    var matches by remember { mutableStateOf<List<WearMatch>?>(null) }
    val scope = rememberCoroutineScope()

    // Refresh each time the watch face/app resumes.
    LifecycleResumeEffect(Unit) {
        scope.launch { matches = runCatching { api.fetchDefaults() }.getOrDefault(emptyList()) }
        onPauseOrDispose { }
    }

    MaterialTheme {
        val listState = rememberScalingLazyListState()
        TimeText()
        when (val data = matches) {
            null -> CenterLoader()
            else -> ScalingLazyColumn(
                state = listState,
                modifier = Modifier.fillMaxSize(),
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                item {
                    Text(
                        text = "Matcha",
                        fontWeight = FontWeight.Bold,
                        fontSize = 18.sp,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth().padding(bottom = 4.dp),
                    )
                }
                if (data.isEmpty()) {
                    item {
                        Text(
                            text = "No matches right now",
                            textAlign = TextAlign.Center,
                            fontSize = 13.sp,
                            color = MaterialTheme.colors.onSurfaceVariant,
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }
                } else {
                    items(data) { WearMatchCard(it) }
                }
            }
        }
    }
}

@Composable
private fun WearMatchCard(match: WearMatch) {
    Card(onClick = {}, modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.fillMaxWidth()) {
            Text(
                text = match.leagueName,
                fontSize = 10.sp,
                color = MaterialTheme.colors.primary,
            )
            ScoreLine(match.homeName, match.homeScore)
            ScoreLine(match.awayName, match.awayScore)
            Text(
                text = when (match.state) {
                    WearMatchState.LIVE -> match.statusDetail.ifBlank { "LIVE" }
                    WearMatchState.FINAL -> "FT"
                    WearMatchState.UPCOMING -> match.statusDetail.ifBlank { "Soon" }
                },
                fontSize = 10.sp,
                color = if (match.state == WearMatchState.LIVE)
                    MaterialTheme.colors.error else MaterialTheme.colors.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun ScoreLine(name: String, score: String?) {
    androidx.compose.foundation.layout.Row(Modifier.fillMaxWidth()) {
        Text(
            text = name,
            fontSize = 13.sp,
            modifier = Modifier.weight(1f),
            maxLines = 1,
        )
        Text(
            text = score ?: "-",
            fontSize = 13.sp,
            fontWeight = FontWeight.Bold,
        )
    }
}

@Composable
private fun CenterLoader() {
    Column(
        Modifier.fillMaxSize(),
        verticalArrangement = Arrangement.Center,
    ) {
        CircularProgressIndicator(modifier = Modifier.fillMaxWidth().padding(20.dp))
    }
}
