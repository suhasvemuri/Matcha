//
//  GamesListView.swift
//  MenuScores
//
//  Created by Daniyal Master on 2025-05-03.
//

import Foundation

@MainActor
class GamesListView: ObservableObject {
    @Published var games: [Event] = []
    /// True only on the very first load, so views can show a spinner instead of
    /// an empty list. Silent on background refreshes (we already have data).
    @Published var isInitialLoading = true
    /// Set when a fetch fails and we have nothing to show, so views can offer a
    /// retry affordance rather than a blank screen.
    @Published var loadFailed = false

    func populateGames(from url: URL) async {
        do {
            self.games = try await getGames().getGamesArray(url: url)
            self.loadFailed = false
        } catch {
            Log.feed.error("Failed to fetch games: \(error.localizedDescription, privacy: .public)")
            self.loadFailed = games.isEmpty
        }
        self.isInitialLoading = false
    }
}

// MARK: Tennis Only

@MainActor
class TennisListView: ObservableObject {
    @Published var tennisGames: [TennisEvent] = []
    @Published var isInitialLoading = true
    @Published var loadFailed = false

    func populateTennis(from url: URL) async {
        do {
            self.tennisGames = try await getGames().getTennisArray(url: url)
            self.loadFailed = false
        } catch {
            Log.feed.error("Failed to fetch tennis games: \(error.localizedDescription, privacy: .public)")
            self.loadFailed = tennisGames.isEmpty
        }
        self.isInitialLoading = false
    }
}
