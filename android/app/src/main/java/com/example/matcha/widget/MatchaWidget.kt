package com.example.matcha.widget

import android.content.Context
import androidx.compose.runtime.Composable
import android.content.ComponentName
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.LocalContext
import androidx.glance.action.actionStartActivity
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.lazy.LazyColumn
import androidx.glance.appwidget.lazy.items
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import androidx.glance.layout.wrapContentHeight
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.matcha.MainActivity
import com.example.matcha.data.FavoritesStore
import com.example.matcha.data.Match
import com.example.matcha.data.MatchState
import com.example.matcha.data.MatchaRepository
import kotlinx.coroutines.flow.first

/** Home-screen widget that lists the user's favorite live/upcoming matches. */
class MatchaWidget : GlanceAppWidget() {

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val store = FavoritesStore(context)
        val leagues = store.favoriteLeagueIds.first()
        val teams = store.favoriteTeamNames.first()
        val matches = runCatching {
            MatchaRepository.get(context).fetchOnce(leagues, teams)
        }.getOrDefault(emptyList()).take(MAX_ROWS)

        provideContent {
            GlanceTheme {
                WidgetBody(matches)
            }
        }
    }

    @Composable
    private fun WidgetBody(matches: List<Match>) {
        Column(
            modifier = GlanceModifier
                .fillMaxSize()
                .background(GlanceTheme.colors.widgetBackground)
                .cornerRadius(16.dp)
                .padding(12.dp)
                .clickable(actionStartActivity(ComponentName(LocalContext.current, MainActivity::class.java))),
        ) {
            Text(
                text = "Matcha",
                style = TextStyle(
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Bold,
                    color = GlanceTheme.colors.onSurface,
                ),
            )
            Spacer(GlanceModifier.height(6.dp))
            if (matches.isEmpty()) {
                Text(
                    text = "No favorite matches right now",
                    style = TextStyle(fontSize = 12.sp, color = GlanceTheme.colors.onSurfaceVariant),
                )
            } else {
                LazyColumn {
                    items(matches) { WidgetMatchRow(it) }
                }
            }
        }
    }

    @Composable
    private fun WidgetMatchRow(match: Match) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = GlanceModifier.fillMaxWidth().padding(vertical = 4.dp),
        ) {
            Column(modifier = GlanceModifier.defaultWeight()) {
                Text(
                    text = "${match.home.abbreviation.ifBlank { match.home.shortName }}  ${match.home.score ?: ""}",
                    style = TextStyle(fontSize = 13.sp, color = GlanceTheme.colors.onSurface),
                )
                Text(
                    text = "${match.away.abbreviation.ifBlank { match.away.shortName }}  ${match.away.score ?: ""}",
                    style = TextStyle(fontSize = 13.sp, color = GlanceTheme.colors.onSurface),
                )
            }
            Spacer(GlanceModifier.width(8.dp))
            Box(
                contentAlignment = Alignment.CenterEnd,
                modifier = GlanceModifier.width(56.dp).wrapContentHeight(),
            ) {
                Text(
                    text = match.statusLabel(),
                    style = TextStyle(
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Medium,
                        color = if (match.state == MatchState.LIVE)
                            ColorProvider(Color(0xFFE5484D))
                        else GlanceTheme.colors.onSurfaceVariant,
                    ),
                )
            }
        }
    }

    private fun Match.statusLabel(): String = when (state) {
        MatchState.LIVE -> statusDetail.ifBlank { "LIVE" }
        MatchState.FINAL -> "FT"
        MatchState.UPCOMING -> statusDetail.ifBlank { "Soon" }
    }

    companion object {
        private const val MAX_ROWS = 8
    }
}
