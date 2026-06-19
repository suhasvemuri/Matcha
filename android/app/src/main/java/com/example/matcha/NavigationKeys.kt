package com.example.matcha

import androidx.navigation3.runtime.NavKey
import kotlinx.serialization.Serializable

@Serializable data object Main : NavKey

@Serializable data object Favorites : NavKey

@Serializable data object Settings : NavKey

@Serializable data class Bracket(val leagueId: String) : NavKey
