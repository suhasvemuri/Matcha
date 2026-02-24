import SwiftUI

struct SoccerLeagueFeed {
    let leagueCode: String
    let leagueTitle: String
    let games: [Event]
}

struct FavoriteSoccerGame: Identifiable {
    let id: String
    let leagueCode: String
    let leagueTitle: String
    let game: Event
}

struct FavoritesMenu: View {
    let soccerFeeds: [SoccerLeagueFeed]
    let cricketMatches: [CricketMatch]

    @AppStorage("iptvM3UURL") private var iptvM3UURL = ""
    @AppStorage("favoriteTeamsCsv") private var legacyFavoriteTeamsCsv = ""
    @AppStorage("favoriteSoccerCsv") private var favoriteSoccerCsv = ""
    @AppStorage("favoriteCricketCsv") private var favoriteCricketCsv = ""
    @AppStorage("favoriteCompetitionsCsv") private var favoriteCompetitionsCsv = ""

    private var soccerTerms: [String] {
        (favoriteSoccerCsv + "," + legacyFavoriteTeamsCsv)
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }

    private var cricketTerms: [String] {
        (favoriteCricketCsv + "," + legacyFavoriteTeamsCsv)
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }

    private var competitionTerms: [String] {
        favoriteCompetitionsCsv
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }

    private var allTermsEmpty: Bool {
        soccerTerms.isEmpty && cricketTerms.isEmpty && competitionTerms.isEmpty
    }

    private var favoriteSoccerGames: [FavoriteSoccerGame] {
        let matches = soccerFeeds.flatMap { feed -> [FavoriteSoccerGame] in
            feed.games.compactMap { game in
                let teamNames = game.competitions.first?.competitors?.compactMap {
                    $0.team?.displayName?.lowercased() ?? $0.team?.name?.lowercased()
                } ?? []

                let matchup = (game.shortName ?? game.name).lowercased()
                let leagueName = feed.leagueTitle.lowercased()

                let teamMatch = soccerTerms.isEmpty ? false : soccerTerms.contains { term in
                    teamNames.contains(where: { $0.contains(term) }) || matchup.contains(term)
                }

                let competitionMatch = competitionTerms.isEmpty ? false : competitionTerms.contains { term in
                    leagueName.contains(term) || matchup.contains(term)
                }

                guard teamMatch || competitionMatch else { return nil }

                return FavoriteSoccerGame(
                    id: "\(feed.leagueCode)-\(game.id)",
                    leagueCode: feed.leagueCode,
                    leagueTitle: feed.leagueTitle,
                    game: game
                )
            }
        }

        return matches.sorted {
            ($0.game.date) < ($1.game.date)
        }
    }

    private var liveSoccerGames: [FavoriteSoccerGame] {
        favoriteSoccerGames.filter { $0.game.status.type.state == "in" }
    }

    private var upcomingSoccerGames: [FavoriteSoccerGame] {
        favoriteSoccerGames.filter { $0.game.status.type.state == "pre" }
    }

    private var favoriteCricketGames: [CricketMatch] {
        cricketMatches.filter { match in
            let haystack = (match.title + " " + match.detail).lowercased()

            let teamMatch = cricketTerms.isEmpty ? false : cricketTerms.contains { haystack.contains($0) }
            let competitionMatch = competitionTerms.isEmpty ? false : competitionTerms.contains { haystack.contains($0) }

            return teamMatch || competitionMatch
        }
    }

    private var liveCricketGames: [CricketMatch] {
        favoriteCricketGames.filter { $0.isLive }
    }

    private var upcomingCricketGames: [CricketMatch] {
        favoriteCricketGames.filter { $0.isUpcoming }
    }

    var body: some View {
        Menu("Favorites") {
            if allTermsEmpty {
                Text("Add favorites in Settings -> Streaming")
                    .foregroundColor(.secondary)
            } else {
                if liveSoccerGames.isEmpty, upcomingSoccerGames.isEmpty, liveCricketGames.isEmpty, upcomingCricketGames.isEmpty {
                    Text("No favorite fixtures found right now")
                        .foregroundColor(.secondary)
                }

                if !liveSoccerGames.isEmpty {
                    Menu("Soccer Live") {
                        ForEach(liveSoccerGames.prefix(10)) { item in
                            soccerGameActions(item)
                        }
                    }
                }

                if !upcomingSoccerGames.isEmpty {
                    Menu("Soccer Next Fixtures") {
                        ForEach(upcomingSoccerGames.prefix(10)) { item in
                            soccerGameActions(item)
                        }
                    }
                }

                if !liveCricketGames.isEmpty {
                    Menu("Cricket Live") {
                        ForEach(liveCricketGames.prefix(10)) { match in
                            cricketMatchActions(match)
                        }
                    }
                }

                if !upcomingCricketGames.isEmpty {
                    Menu("Cricket Next Fixtures") {
                        ForEach(upcomingCricketGames.prefix(10)) { match in
                            cricketMatchActions(match)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func soccerGameActions(_ item: FavoriteSoccerGame) -> some View {
        let game = item.game
        let channels = broadcastNames(for: game)

        Menu("[\(item.leagueTitle)] \(displayText(for: game, league: item.leagueCode))") {
            Button("Open Match") {
                if let href = game.links?.first?.href, let url = URL(string: href) {
                    NSWorkspace.shared.open(url)
                }
            }

            if let standings = LeagueLinks.standingsURL(for: item.leagueCode) {
                Button("Open Standings") {
                    NSWorkspace.shared.open(standings)
                }
            }

            if let listing = LeagueLinks.liveSoccerTVSearchURL(for: game) {
                Button("Find Broadcast Listings") {
                    NSWorkspace.shared.open(listing)
                }
            }

            if !channels.isEmpty {
                Divider()
                Text("Channels")
                ForEach(channels, id: \.self) { channel in
                    Text(channel)
                }

                if !iptvM3UURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Divider()
                    ForEach(channels, id: \.self) { channel in
                        Button("Play \(channel)") {
                            Task {
                                if let url = await IPTVResolver.shared.resolveStreamURL(
                                    channelNames: [channel],
                                    m3uURLString: iptvM3UURL
                                ) {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cricketMatchActions(_ match: CricketMatch) -> some View {
        Menu(match.scoreLine) {
            if !match.status.isEmpty {
                Text(match.status)
            } else if !match.detail.isEmpty {
                Text(match.detail)
            }

            Button("Open Scorecard") {
                NSWorkspace.shared.open(match.url)
            }

            Button("Open Points Tables") {
                if let url = URL(string: "https://www.cricbuzz.com/cricket-stats/points-table") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    private func broadcastNames(for game: Event) -> [String] {
        guard let broadcasts = game.competitions.first?.broadcasts else { return [] }
        return Array(Set(broadcasts.flatMap { $0.names ?? [] })).sorted()
    }
}
