package com.example.matcha.ui.onboarding

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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.selection.toggleable
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.example.matcha.data.FavoritesStore
import com.example.matcha.data.Leagues
import com.example.matcha.theme.CompetitionThemes
import com.example.matcha.ui.common.Crest
import kotlinx.coroutines.launch

private val POPULAR = listOf("FFWC", "EPL", "UEFA", "ESP", "GER", "ITA", "IPL", "CWC", "FORMULA1")

@Composable
fun OnboardingScreen(onDone: () -> Unit) {
    val context = androidx.compose.ui.platform.LocalContext.current
    val store = remember { FavoritesStore(context) }
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    val selected = remember { mutableStateMapOf<String, Boolean>().apply { Leagues.defaultFavoriteIds.forEach { put(it, true) } } }
    val theme = CompetitionThemes.forLeague("FFWC")

    Box(
        Modifier.fillMaxSize().background(
            Brush.verticalGradient(listOf(theme.gradientTop, theme.gradientBottom, MaterialTheme.colorScheme.background)),
        ),
    ) {
        Column(Modifier.fillMaxSize().padding(24.dp)) {
            Spacer(Modifier.height(40.dp))
            Text("Welcome to Matcha", style = MaterialTheme.typography.headlineLarge, fontWeight = FontWeight.ExtraBold, color = MaterialTheme.colorScheme.onBackground)
            Spacer(Modifier.height(8.dp))
            Text(
                "Pick a few competitions to follow. You can change these any time.",
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.height(20.dp))
            LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                items(POPULAR.mapNotNull { Leagues.byId(it) }, key = { it.id }) { league ->
                    val checked = selected[league.id] == true
                    Surface(
                        color = MaterialTheme.colorScheme.surfaceContainer,
                        shape = MaterialTheme.shapes.large,
                        modifier = Modifier.fillMaxWidth().toggleable(checked) { selected[league.id] = it },
                    ) {
                        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 14.dp), verticalAlignment = Alignment.CenterVertically) {
                            Column(Modifier.weight(1f)) {
                                Text(league.displayName, style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onSurface)
                                league.country?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                            }
                            Checkbox(checked = checked, onCheckedChange = null)
                        }
                    }
                }
            }
            Spacer(Modifier.height(12.dp))
            Button(
                onClick = {
                    scope.launch {
                        Leagues.all.forEach { l ->
                            store.setLeagueFavorite(l.id, selected[l.id] == true)
                        }
                        onDone()
                    }
                },
                modifier = Modifier.fillMaxWidth(),
            ) { Text("Get started") }
            Spacer(Modifier.height(8.dp))
        }
    }
}
