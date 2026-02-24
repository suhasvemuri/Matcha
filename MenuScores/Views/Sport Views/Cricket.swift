import SwiftUI

struct CricketMenu: View {
    let title: String
    @ObservedObject var viewModel: CricketListView

    @Binding var currentTitle: String
    @Binding var currentGameID: String
    @Binding var currentGameState: String
    @Binding var previousGameState: String?

    @AppStorage("refreshInterval") private var selectedOption = "15 seconds"
    @AppStorage("favoriteTeamsCsv") private var legacyFavoriteTeamsCsv = ""
    @AppStorage("favoriteCricketCsv") private var favoriteCricketCsv = ""

    @State private var pinnedByMenubar = false

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
        (favoriteCricketCsv + "," + legacyFavoriteTeamsCsv)
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }

    private var filteredMatches: [CricketMatch] {
        guard !teamFilters.isEmpty else { return viewModel.matches }

        return viewModel.matches.filter { match in
            let haystack = [
                match.title,
                match.detail,
                match.team1Name,
                match.team2Name,
                match.seriesName,
                match.matchDesc,
            ].joined(separator: " ").lowercased()

            return teamFilters.contains { haystack.contains($0) }
        }
    }

    var body: some View {
        Menu(title) {
            if filteredMatches.isEmpty {
                Text("No cricket matches for current filters")
                    .foregroundColor(.secondary)

                Button("Open Cricbuzz Live Scores") {
                    if let url = URL(string: "https://www.cricbuzz.com/cricket-match/live-scores") {
                        NSWorkspace.shared.open(url)
                    }
                }
            } else {
                ForEach(filteredMatches) { match in
                    Menu {
                        Button("Pin Match to Menubar") {
                            currentTitle = match.menubarText
                            currentGameID = "cricket:\(match.id)"
                            currentGameState = match.state.lowercased()
                            pinnedByMenubar = true
                        }

                        Button("Open Scorecard") {
                            NSWorkspace.shared.open(match.url)
                        }

                        Button("Open Standings / Points Tables") {
                            if let url = URL(string: "https://www.cricbuzz.com/cricket-stats/points-table") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(match.scoreLine)
                                .fontWeight(.semibold)

                            if !match.status.isEmpty {
                                Text(match.status)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else if !match.matchDesc.isEmpty {
                                Text(match.matchDesc)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            Task {
                await viewModel.populateMatches()
            }
        }
        .onReceive(Timer.publish(every: refreshInterval, on: .main, in: .common).autoconnect()) { _ in
            Task {
                await viewModel.populateMatches()

                if pinnedByMenubar,
                   currentGameID.hasPrefix("cricket:"),
                   let pinnedID = currentGameID.split(separator: ":").last,
                   let updated = viewModel.matches.first(where: { $0.id == String(pinnedID) }) {
                    currentTitle = updated.menubarText
                    currentGameState = updated.state.lowercased()
                }
            }
        }
    }
}
