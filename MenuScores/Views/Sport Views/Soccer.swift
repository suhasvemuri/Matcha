//
//  Soccer.swift
//  MenuScores
//
//  Created by Daniyal Master on 2025-08-02.
//

import DynamicNotchKit
import SwiftUI

struct SoccerMenu: View {
    let title: String
    @ObservedObject var viewModel: GamesListView
    let league: String
    let fetchURL: URL

    @StateObject private var notchViewModel = NotchViewModel()

    @State private var pinnedByNotch = false
    @State private var pinnedByMenubar = false

    @Binding var currentTitle: String
    @Binding var currentGameID: String
    @Binding var currentGameState: String
    @Binding var previousGameState: String?

    @AppStorage("enableNotch") private var enableNotch = true
    @AppStorage("notchScreenIndex") private var notchScreenIndex = 0

    @AppStorage("refreshInterval") private var selectedOption = "15 seconds"
    @AppStorage("notiGameStart") private var notiGameStart = false
    @AppStorage("notiGameComplete") private var notiGameComplete = false
    @AppStorage("iptvM3UURL") private var iptvM3UURL = ""
    @AppStorage("favoriteTeamsCsv") private var legacyFavoriteTeamsCsv = ""
    @AppStorage("favoriteSoccerCsv") private var favoriteSoccerCsv = ""
    @State private var standingsTitle = ""
    @State private var standingsRows: [SoccerStandingRow] = []

    private var refreshInterval: TimeInterval {
        switch selectedOption {
        case "10 seconds": return 10
        case "15 seconds": return 15
        case "20 seconds": return 20
        case "30 seconds": return 30
        case "40 seconds": return 40
        case "50 seconds": return 50
        case "1 minute": return 60
        case "2 minutes": return 120
        case "5 minutes": return 300
        default: return 15
        }
    }

    private var teamFilters: [String] {
        (favoriteSoccerCsv + "," + legacyFavoriteTeamsCsv)
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }

    private var filteredGames: [Event] {
        guard !teamFilters.isEmpty else { return viewModel.games }

        return viewModel.games.filter { game in
            let names = game.competitions
                .first?
                .competitors?
                .compactMap { $0.team?.displayName?.lowercased() } ?? []

            return teamFilters.contains { filter in
                names.contains { $0.contains(filter) }
            }
        }
    }

    private func broadcastNames(for game: Event) -> [String] {
        guard let broadcasts = game.competitions.first?.broadcasts else { return [] }
        return Array(
            Set(
                broadcasts
                    .flatMap { $0.names ?? [] }
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        ).sorted()
    }

    var body: some View {
        Menu(title) {
            if !standingsRows.isEmpty {
                Menu("Standings: \(standingsTitle)") {
                    ForEach(standingsRows) { row in
                        Text("\(row.rank). \(row.teamName)  \(row.points) pts  GP \(row.played)  (\(row.record))")
                    }

                    if let standingsURL = LeagueLinks.standingsURL(for: league) {
                        Divider()
                        Button("Open Full Standings") {
                            NSWorkspace.shared.open(standingsURL)
                        }
                    }
                }
                Divider().padding(.bottom, 2)
            }

            Text(formattedDate(from: viewModel.games.first?.date ?? "Invalid Date"))
                .font(.headline)
            Divider().padding(.bottom)

            if !filteredGames.isEmpty {
                ForEach(Array(filteredGames.enumerated()), id: \.1.id) { _, game in
                    Menu {
                        Button {
                            currentTitle = displayText(for: game, league: league)
                            currentGameID = game.id
                            currentGameState = game.status.type.state

                            pinnedByMenubar = true
                            pinnedByNotch = false
                        } label: {
                            HStack {
                                Image(systemName: "menubar.rectangle")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 20, height: 20)
                                Text("Pin Game to Menubar")
                            }
                        }

                        if enableNotch {
                            Button {
                                currentGameID = game.id
                                currentGameState = game.status.type.state

                                pinnedByNotch = true
                                pinnedByMenubar = false

                                notchViewModel.game = game

                                Task {
                                    if let existingNotch = NotchViewModel.shared.notch {
                                        await existingNotch.hide()
                                        NotchViewModel.shared.game = nil
                                        NotchViewModel.shared.currentGameID = ""
                                        NotchViewModel.shared.currentGameState = ""
                                        NotchViewModel.shared.previousGameState = ""
                                        NotchViewModel.shared.notch = nil
                                    }

                                    let newNotch = DynamicNotch(
                                        hoverBehavior: .all,
                                        style: .notch
                                    ) {
                                        Info(notchViewModel: notchViewModel, sport: "Soccer", league: "\(league)")
                                    } compactLeading: {
                                        CompactLeading(notchViewModel: notchViewModel, sport: "Soccer")
                                    } compactTrailing: {
                                        CompactTrailing(notchViewModel: notchViewModel, sport: "Soccer")
                                    }

                                    NotchViewModel.shared.notch = newNotch
                                    await newNotch.compact(on: NSScreen.screens[notchScreenIndex])
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "macbook")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 20, height: 20)
                                    Text("Pin Game to Notch")
                                }
                            }
                        }

                        Button {
                            if let urlString = game.links?.first?.href, let url = URL(string: urlString) {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            HStack {
                                Image(systemName: "info.circle")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 20, height: 20)
                                Text("View Game Details")
                            }
                        }

                        if let standingsURL = LeagueLinks.standingsURL(for: league) {
                            Button {
                                NSWorkspace.shared.open(standingsURL)
                            } label: {
                                HStack {
                                    Image(systemName: "list.number")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 20, height: 20)
                                    Text("View Standings")
                                }
                            }
                        }

                        let channels = broadcastNames(for: game)
                        if !channels.isEmpty {
                            Divider()
                            Text("Broadcast")
                                .font(.caption)
                            ForEach(channels, id: \.self) { channel in
                                Text(channel)
                                    .font(.caption2)
                            }
                        }

                        if !iptvM3UURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                           !channels.isEmpty {
                            Menu {
                                ForEach(channels, id: \.self) { channel in
                                    Button(channel) {
                                        Task {
                                            if let streamURL = await IPTVResolver.shared.resolveStreamURL(
                                                channelNames: [channel],
                                                m3uURLString: iptvM3UURL
                                            ) {
                                                NSWorkspace.shared.open(streamURL)
                                            } else if let playlistURL = URL(string: iptvM3UURL) {
                                                NSWorkspace.shared.open(playlistURL)
                                            }
                                        }
                                    }
                                }

                                Divider()
                                Button("Open IPTV Playlist URL") {
                                    if let playlistURL = URL(string: iptvM3UURL) {
                                        NSWorkspace.shared.open(playlistURL)
                                    }
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "play.circle")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 20, height: 20)
                                    Text("Play on IPTV")
                                }
                            }
                        }

                        if let listingURL = LeagueLinks.liveSoccerTVSearchURL(for: game) {
                            Button {
                                NSWorkspace.shared.open(listingURL)
                            } label: {
                                HStack {
                                    Image(systemName: "tv")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 20, height: 20)
                                    Text("Find Broadcast Listings")
                                }
                            }
                        }
                    } label: {
                        HStack {
                            AsyncImage(
                                url: URL(string: game.competitions[0].competitors?[1].team?.logo ?? "https://a.espncdn.com/combiner/i?img=/redesign/assets/img/icons/ESPN-icon-soccer.png&h=80&w=80&scale=crop&cquality=40")
                            ) { image in
                                image.resizable().scaledToFit()
                            } placeholder: {
                                ProgressView()
                            }
                            .frame(width: 40, height: 40)

                            Text(displayText(for: game, league: league))
                        }
                    }
                }
            } else {
                Text(teamFilters.isEmpty ? "Loading games..." : "No soccer games match favorites")
                    .foregroundColor(.gray)
                    .padding()
            }
        }
        .onAppear {
            LeagueSelectionModel.shared.currentLeague = league
            Task {
                await viewModel.populateGames(from: fetchURL)
                await refreshStandingsIfNeeded(force: true)
            }
        }
        .onReceive(
            Timer.publish(every: refreshInterval, on: .main, in: .common).autoconnect()
        ) { _ in
            Task {
                await viewModel.populateGames(from: fetchURL)
                await refreshStandingsIfNeeded()
                if let updatedGame = viewModel.games.first(where: { $0.id == currentGameID }) {
                    if pinnedByMenubar {
                        currentTitle = displayText(for: updatedGame, league: league)
                    } else if pinnedByNotch {
                        currentTitle = ""
                    }

                    let newState = updatedGame.status.type.state

                    if notiGameStart && previousGameState != "in" && newState == "in" {
                        gameStartNotification(gameId: currentGameID, gameTitle: currentTitle, newState: newState)
                    }
                    if notiGameComplete && previousGameState != "post" && newState == "post" {
                        gameCompleteNotification(gameId: currentGameID, gameTitle: currentTitle, newState: newState)
                    }

                    previousGameState = newState
                    currentGameState = newState

                    if pinnedByNotch {
                        notchViewModel.game = updatedGame
                    }
                }
            }
        }
    }

    private func refreshStandingsIfNeeded(force: Bool = false) async {
        if !force, !standingsRows.isEmpty { return }
        if let result = await SoccerStandingsService.shared.topStandings(for: league, maxRows: 5) {
            standingsTitle = result.title
            standingsRows = result.rows
        }
    }
}
