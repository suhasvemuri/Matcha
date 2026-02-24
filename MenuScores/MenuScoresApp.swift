//
//  MenuScoresApp.swift
//  MenuScores
//
//  Created by Daniyal Master on 2025-05-03.
//

import SwiftUI

class LeagueSelectionModel: ObservableObject {
    @Published var currentLeague: String = ""
}

extension LeagueSelectionModel {
    static let shared = LeagueSelectionModel()
}

@main
struct MenuScoresApp: App {
    // Refresh Interval Settings

    @AppStorage("refreshInterval") private var selectedOption = "15 seconds"

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

    // Toggled League Settings

    @AppStorage("enableNHL") private var enableNHL = false
    @AppStorage("enableHNCAAM") private var enableHNCAAM = false
    @AppStorage("enableHNCAAF") private var enableHNCAAF = false

    @AppStorage("enableNBA") private var enableNBA = false
    @AppStorage("enableWNBA") private var enableWNBA = false
    @AppStorage("enableNCAAM") private var enableNCAAM = false
    @AppStorage("enableNCAAF") private var enableNCAAF = false

    @AppStorage("enableNFL") private var enableNFL = false
    @AppStorage("enableFNCAA") private var enableFNCAA = false

    @AppStorage("enableMLB") private var enableMLB = false
    @AppStorage("enableBNCAA") private var enableBNCAA = false
    @AppStorage("enableSNCAA") private var enableSNCAA = false

    @AppStorage("enableF1") private var enableF1 = false
    @AppStorage("enableNC") private var enableNC = false
    @AppStorage("enableNCS") private var enableNCS = false
    @AppStorage("enableNCT") private var enableNCT = false
    @AppStorage("enableIRL") private var enableIRL = false

    @AppStorage("enablePGA") private var enablePGA = false
    @AppStorage("enableLPGA") private var enableLPGA = false

    @AppStorage("enableMLS") private var enableMLS = true
    @AppStorage("enableNWSL") private var enableNWSL = false
    @AppStorage("enableUEFA") private var enableUEFA = false
    @AppStorage("enableEUEFA") private var enableEUEFA = false
    @AppStorage("enableWUEFA") private var enableWUEFA = false
    @AppStorage("enableMEX") private var enableMEX = false
    @AppStorage("enableFRA") private var enableFRA = false
    @AppStorage("enableNED") private var enableNED = false
    @AppStorage("enablePOR") private var enablePOR = false
    @AppStorage("enableEPL") private var enableEPL = false
    @AppStorage("enableWEPL") private var enableWEPL = false
    @AppStorage("enableESP") private var enableESP = false
    @AppStorage("enableGER") private var enableGER = false
    @AppStorage("enableITA") private var enableITA = false

    @AppStorage("enableFFWC") private var enableFFWC = false
    @AppStorage("enableFFWWC") private var enableFFWWC = false
    @AppStorage("enableFFWCQUEFA") private var enableFFWCQUEFA = false
    @AppStorage("enableCONCACAF") private var enableCONCACAF = false
    @AppStorage("enableCONMEBOL") private var enableCONMEBOL = false
    @AppStorage("enableCAF") private var enableCAF = false
    @AppStorage("enableAFC") private var enableAFC = false
    @AppStorage("enableOFC") private var enableOFC = false
    @AppStorage("enableCricket") private var enableCricket = true

    @AppStorage("enableATP") private var enableATP = false
    @AppStorage("enableWTA") private var enableWTA = false

    @AppStorage("enableUFC") private var enableUFC = false

    @AppStorage("enableNLL") private var enableNLL = false
    @AppStorage("enablePLL") private var enablePLL = false
    @AppStorage("enableLNCAAM") private var enableLNCAAM = false
    @AppStorage("enableLNCAAF") private var enableLNCAAF = false

    @AppStorage("enableVNCAAM") private var enableVNCAAM = false
    @AppStorage("enableVNCAAF") private var enableVNCAAF = false

    @AppStorage("enableOMIHC") private var enableOMIHC = false
    @AppStorage("enableOWIHC") private var enableOWIHC = false

    private func refreshAllLeagues() async {
        // Core + selected optional feeds.
        if enableNBA { await nbaVM.populateGames(from: Scoreboard.Urls.nba) }
        if enableNFL { await nflVM.populateGames(from: Scoreboard.Urls.nfl) }
        if enableF1 { await f1VM.populateGames(from: Scoreboard.Urls.f1) }

        if enableMLS { await mlsVM.populateGames(from: Scoreboard.Urls.mls) }
        if enableNWSL { await nwslVM.populateGames(from: Scoreboard.Urls.nwsl) }
        if enableUEFA { await uefaVM.populateGames(from: Scoreboard.Urls.uefa) }
        if enableEUEFA { await euefaVM.populateGames(from: Scoreboard.Urls.euefa) }
        if enableWUEFA { await wuefaVM.populateGames(from: Scoreboard.Urls.wuefa) }
        if enableEPL { await eplVM.populateGames(from: Scoreboard.Urls.epl) }
        if enableWEPL { await weplVM.populateGames(from: Scoreboard.Urls.wepl) }
        if enableESP { await espVM.populateGames(from: Scoreboard.Urls.esp) }
        if enableGER { await gerVM.populateGames(from: Scoreboard.Urls.ger) }
        if enableITA { await itaVM.populateGames(from: Scoreboard.Urls.ita) }
        if enableMEX { await mexVM.populateGames(from: Scoreboard.Urls.mex) }
        if enableFRA { await fraVM.populateGames(from: Scoreboard.Urls.fra) }
        if enableNED { await nedVM.populateGames(from: Scoreboard.Urls.ned) }
        if enablePOR { await porVM.populateGames(from: Scoreboard.Urls.por) }
        if enableFFWC { await ffwcVM.populateGames(from: Scoreboard.Urls.ffwc) }
        if enableFFWWC { await ffwwcVM.populateGames(from: Scoreboard.Urls.ffwwc) }
        if enableFFWCQUEFA { await ffwcquefaVM.populateGames(from: Scoreboard.Urls.ffwcquefa) }
        if enableCONMEBOL { await conmebolVM.populateGames(from: Scoreboard.Urls.conmebol) }
        if enableCONCACAF { await concacafVM.populateGames(from: Scoreboard.Urls.concacaf) }
        if enableCAF { await cafVM.populateGames(from: Scoreboard.Urls.caf) }
        if enableAFC { await afcVM.populateGames(from: Scoreboard.Urls.afc) }
        if enableOFC { await ofcVM.populateGames(from: Scoreboard.Urls.ofc) }
        if enableCricket { await cricketVM.populateMatches() }
    }

    private func clearPinnedGame() {
        currentTitle = ""
        currentGameID = ""
        currentGameState = ""
        previousGameState = nil

        Task {
            if let notch = NotchViewModel.shared.notch {
                await notch.hide()
            }
            NotchViewModel.shared.game = nil
            NotchViewModel.shared.currentGameID = ""
            NotchViewModel.shared.currentGameState = ""
            NotchViewModel.shared.previousGameState = ""
            NotchViewModel.shared.notch = nil
        }
    }

    private func openPreferences() {
        if #available(macOS 14, *) {
            let environment = EnvironmentValues()
            environment.openSettings()
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // Notification Settings

    @AppStorage("notiGameStart") private var notiGameStart = false
    @AppStorage("notiGameComplete") private var notiGameComplete = false

    // Title State Settings

    @State var currentTitle: String = ""
    @State var currentGameID: String = "0"
    @State var currentGameState: String = "pre"
    @State private var previousGameState: String? = nil

    // Notch Data

    @StateObject private var notchViewModel = NotchViewModel()

    // Notch Behaviors

    @AppStorage("enableNotch") private var enableNotch = true
    @AppStorage("notchScreenIndex") private var notchScreenIndex = 0

    // League Fetching

    @StateObject private var nhlVM = GamesListView()
    @StateObject private var hncaamVM = GamesListView()
    @StateObject private var hncaafVM = GamesListView()

    @StateObject private var nbaVM = GamesListView()
    @StateObject private var wnbaVM = GamesListView()
    @StateObject private var ncaamVM = GamesListView()
    @StateObject private var ncaafVM = GamesListView()

    @StateObject private var nflVM = GamesListView()
    @StateObject private var fncaaVM = GamesListView()

    @StateObject private var mlbVM = GamesListView()
    @StateObject private var bncaaVM = GamesListView()
    @StateObject private var sncaaVM = GamesListView()

    @StateObject private var f1VM = GamesListView()
    @StateObject private var ncVM = GamesListView()
    @StateObject private var ncsVM = GamesListView()
    @StateObject private var nctVM = GamesListView()
    @StateObject private var irlVM = GamesListView()

    @StateObject private var pgaVM = GamesListView()
    @StateObject private var lpgaVM = GamesListView()

    @StateObject private var uefaVM = GamesListView()
    @StateObject private var euefaVM = GamesListView()
    @StateObject private var wuefaVM = GamesListView()
    @StateObject private var mlsVM = GamesListView()
    @StateObject private var nwslVM = GamesListView()
    @StateObject private var mexVM = GamesListView()
    @StateObject private var fraVM = GamesListView()
    @StateObject private var nedVM = GamesListView()
    @StateObject private var porVM = GamesListView()
    @StateObject private var eplVM = GamesListView()
    @StateObject private var weplVM = GamesListView()
    @StateObject private var espVM = GamesListView()
    @StateObject private var gerVM = GamesListView()
    @StateObject private var itaVM = GamesListView()

    @StateObject private var ffwcVM = GamesListView()
    @StateObject private var ffwwcVM = GamesListView()
    @StateObject private var ffwcquefaVM = GamesListView()
    @StateObject private var conmebolVM = GamesListView()
    @StateObject private var concacafVM = GamesListView()
    @StateObject private var cafVM = GamesListView()
    @StateObject private var afcVM = GamesListView()
    @StateObject private var ofcVM = GamesListView()

    @StateObject private var atpVM = TennisListView()
    @StateObject private var wtaVM = TennisListView()

    @StateObject private var ufcVM = GamesListView()

    @StateObject private var nllVM = GamesListView()
    @StateObject private var pllVM = GamesListView()
    @StateObject private var lncaamVM = GamesListView()
    @StateObject private var lncaafVM = GamesListView()

    @StateObject private var vncaamVM = GamesListView()
    @StateObject private var vncaafVM = GamesListView()

    @StateObject private var omihcVM = GamesListView()
    @StateObject private var owihcVM = GamesListView()
    @StateObject private var cricketVM = CricketListView()

    private var soccerFeeds: [SoccerLeagueFeed] {
        var feeds: [SoccerLeagueFeed] = []
        if enableMLS { feeds.append(.init(leagueCode: "MLS", leagueTitle: "MLS", games: mlsVM.games)) }
        if enableNWSL { feeds.append(.init(leagueCode: "NWSL", leagueTitle: "NWSL", games: nwslVM.games)) }
        if enableUEFA { feeds.append(.init(leagueCode: "UEFA", leagueTitle: "Champions League", games: uefaVM.games)) }
        if enableEUEFA { feeds.append(.init(leagueCode: "EUEFA", leagueTitle: "Europa League", games: euefaVM.games)) }
        if enableWUEFA { feeds.append(.init(leagueCode: "WUEFA", leagueTitle: "Women's Champions League", games: wuefaVM.games)) }
        if enableEPL { feeds.append(.init(leagueCode: "EPL", leagueTitle: "Premier League", games: eplVM.games)) }
        if enableWEPL { feeds.append(.init(leagueCode: "WEPL", leagueTitle: "Women's Super League", games: weplVM.games)) }
        if enableESP { feeds.append(.init(leagueCode: "ESP", leagueTitle: "La Liga", games: espVM.games)) }
        if enableGER { feeds.append(.init(leagueCode: "GER", leagueTitle: "Bundesliga", games: gerVM.games)) }
        if enableITA { feeds.append(.init(leagueCode: "ITA", leagueTitle: "Serie A", games: itaVM.games)) }
        if enableMEX { feeds.append(.init(leagueCode: "MEX", leagueTitle: "Liga MX", games: mexVM.games)) }
        if enableFRA { feeds.append(.init(leagueCode: "FRA", leagueTitle: "Ligue 1", games: fraVM.games)) }
        if enableNED { feeds.append(.init(leagueCode: "NED", leagueTitle: "Eredivisie", games: nedVM.games)) }
        if enablePOR { feeds.append(.init(leagueCode: "POR", leagueTitle: "Primeira Liga", games: porVM.games)) }
        if enableFFWC { feeds.append(.init(leagueCode: "FFWC", leagueTitle: "FIFA World Cup", games: ffwcVM.games)) }
        if enableFFWWC { feeds.append(.init(leagueCode: "FFWWC", leagueTitle: "FIFA Women's World Cup", games: ffwwcVM.games)) }
        if enableFFWCQUEFA { feeds.append(.init(leagueCode: "FFWCQUEFA", leagueTitle: "FIFA WC UEFA Qualifiers", games: ffwcquefaVM.games)) }
        if enableCONMEBOL { feeds.append(.init(leagueCode: "CONMEBOL", leagueTitle: "FIFA WC CONMEBOL Qualifiers", games: conmebolVM.games)) }
        if enableCONCACAF { feeds.append(.init(leagueCode: "CONCACAF", leagueTitle: "FIFA WC CONCACAF Qualifiers", games: concacafVM.games)) }
        if enableCAF { feeds.append(.init(leagueCode: "CAF", leagueTitle: "FIFA WC African Qualifiers", games: cafVM.games)) }
        if enableAFC { feeds.append(.init(leagueCode: "AFC", leagueTitle: "FIFA WC Asian Qualifiers", games: afcVM.games)) }
        if enableOFC { feeds.append(.init(leagueCode: "OFC", leagueTitle: "FIFA WC Oceanian Qualifiers", games: ofcVM.games)) }
        return feeds
    }

    var body: some Scene {
        MenuBarExtra {
            MatchaDashboardView(
                soccerFeeds: soccerFeeds,
                cricketMatches: cricketVM.matches,
                currentTitle: $currentTitle,
                currentGameID: $currentGameID,
                currentGameState: $currentGameState,
                refreshAction: {
                    Task { await refreshAllLeagues() }
                },
                clearPinnedAction: {
                    clearPinnedGame()
                },
                openPreferencesAction: {
                    openPreferences()
                },
                quitAction: {
                    NSApplication.shared.terminate(nil)
                }
            )
        } label: {
            HStack {
                Image(systemName: "soccerball")
                    .symbolRenderingMode(.monochrome)
                Text(currentTitle)
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            if #available(macOS 15.0, *) {
                SettingsView()
                    .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
                    .containerBackground(.thickMaterial, for: .window)
            } else {
                SettingsView()
            }
        }

        .commands {
            CommandGroup(replacing: .help) {
                Button("Matcha Help") {
                    if let url = URL(string: "https://github.com/daniyalmaster693/MenuScores") {
                        NSWorkspace.shared.open(url)
                    }
                }

                Divider()

                Button("Feedback") {
                    if let url = URL(string: "https://github.com/daniyalmaster693/MenuScores/issues/new") {
                        NSWorkspace.shared.open(url)
                    }
                }

                Button("Changelog") {
                    if let url = URL(string: "https://github.com/daniyalmaster693/MenuScores/releases") {
                        NSWorkspace.shared.open(url)
                    }
                }

                Button("License") {
                    if let url = URL(string: "https://github.com/daniyalmaster693/MenuScores/blob/main/License") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }
}
