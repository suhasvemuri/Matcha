//
//  FeedPlaceholder.swift
//  MenuScores
//
//  Shared placeholder shown inside a sport `Menu` when there are no rows to
//  display. Distinguishes the three states that used to all read
//  "Loading games...": first load, load failure, and a genuinely empty feed
//  (optionally because a favorites filter excluded everything). Menus only
//  render a narrow set of views reliably, so this stays Text-based.
//

import SwiftUI

struct FeedPlaceholder: View {
    /// Plural noun for the feed, e.g. "soccer games", "matches", "races".
    let noun: String
    /// True before the first successful (or failed) fetch completes.
    let isLoading: Bool
    /// True when the last fetch failed and there is nothing cached to show.
    let loadFailed: Bool
    /// True when games exist but a favorites filter excluded them all.
    var filteredOutByFavorites: Bool = false

    private var message: String {
        if isLoading { return "Loading \(noun)…" }
        if loadFailed { return "Couldn't load \(noun) — retrying…" }
        if filteredOutByFavorites { return "No \(noun) match your favorites" }
        return "No \(noun) scheduled"
    }

    var body: some View {
        Text(message)
            .foregroundColor(.gray)
            .padding()
    }
}
