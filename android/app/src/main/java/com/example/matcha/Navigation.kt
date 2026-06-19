package com.example.matcha

import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.navigation3.runtime.entryProvider
import androidx.navigation3.runtime.rememberNavBackStack
import androidx.navigation3.ui.NavDisplay
import com.example.matcha.ui.bracket.BracketScreen
import com.example.matcha.ui.favorites.FavoritesScreen
import com.example.matcha.ui.main.MainScreen

@Composable
fun MainNavigation() {
  val backStack = rememberNavBackStack(Main)

  NavDisplay(
    backStack = backStack,
    onBack = { backStack.removeLastOrNull() },
    entryProvider =
      entryProvider {
        entry<Main> {
          MainScreen(onItemClick = { navKey -> backStack.add(navKey) })
        }
        entry<Favorites> {
          FavoritesScreen(onBack = { backStack.removeLastOrNull() })
        }
        entry<Settings> {
          com.example.matcha.ui.settings.SettingsScreen(onBack = { backStack.removeLastOrNull() })
        }
        entry<Search> {
          com.example.matcha.ui.search.SearchScreen(onBack = { backStack.removeLastOrNull() })
        }
        entry<Bracket> { key ->
          BracketScreen(leagueId = key.leagueId, onBack = { backStack.removeLastOrNull() })
        }
      },
  )
}
