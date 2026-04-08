import SwiftUI

private enum SearchKindFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case team = "Teams"
    case competition = "Competitions"
    case country = "Countries"

    var id: String { rawValue }
}

private enum SearchSportFilter: String, CaseIterable, Identifiable {
    case all = "All Sports"
    case soccer = "Soccer"
    case cricket = "Cricket"

    var id: String { rawValue }
}

struct StreamingSettingsView: View {
    @AppStorage("iptvM3UURL") private var iptvM3UURL = ""
    @AppStorage("iptvEPGURL") private var iptvEPGURL = ""
    @AppStorage("enableStreamedProvider") private var enableStreamedProvider = true
    @AppStorage("streamedBaseURL") private var streamedBaseURL = "https://streamed.st"
    @AppStorage("favoriteTeamsCsv") private var legacyFavoriteTeamsCsv = ""
    @AppStorage("favoriteSoccerCsv") private var legacyFavoriteSoccerCsv = ""
    @AppStorage("favoriteCricketCsv") private var legacyFavoriteCricketCsv = ""
    @AppStorage("favoriteCompetitionsCsv") private var legacyFavoriteCompetitionsCsv = ""
    @AppStorage(FavoriteSelectionsStore.storageKey) private var favoriteSelectionsJSON = ""

    @State private var query = ""
    @State private var kindFilter: SearchKindFilter = .all
    @State private var sportFilter: SearchSportFilter = .all
    @State private var soccerTeamCatalog: [FavoriteCatalogItem] = []
    @State private var isLoadingSoccerTeams = false
    @State private var loadedSoccerTeams = false

    private var hasM3U: Bool {
        !iptvM3UURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasEPG: Bool {
        !iptvEPGURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private let soccerCompetitions: [FavoriteCatalogItem] = [
        .init(kind: .competition, sport: .soccer, name: "MLS", country: "United States"),
        .init(kind: .competition, sport: .soccer, name: "NWSL", country: "United States"),
        .init(kind: .competition, sport: .soccer, name: "Premier League", country: "England"),
        .init(kind: .competition, sport: .soccer, name: "UEFA Champions League", country: "Europe"),
        .init(kind: .competition, sport: .soccer, name: "UEFA Europa League", country: "Europe"),
        .init(kind: .competition, sport: .soccer, name: "La Liga", country: "Spain"),
        .init(kind: .competition, sport: .soccer, name: "Bundesliga", country: "Germany"),
        .init(kind: .competition, sport: .soccer, name: "Serie A", country: "Italy"),
        .init(kind: .competition, sport: .soccer, name: "Ligue 1", country: "France"),
        .init(kind: .competition, sport: .soccer, name: "Eredivisie", country: "Netherlands"),
        .init(kind: .competition, sport: .soccer, name: "Primeira Liga", country: "Portugal"),
        .init(kind: .competition, sport: .soccer, name: "Liga MX", country: "Mexico"),
        .init(kind: .competition, sport: .soccer, name: "FIFA World Cup", country: "International"),
        .init(kind: .competition, sport: .soccer, name: "FIFA Women's World Cup", country: "International"),
        .init(kind: .competition, sport: .soccer, name: "FIFA WC UEFA Qualifiers", country: "Europe"),
        .init(kind: .competition, sport: .soccer, name: "FIFA WC CONMEBOL Qualifiers", country: "South America"),
        .init(kind: .competition, sport: .soccer, name: "FIFA WC CONCACAF Qualifiers", country: "North America"),
        .init(kind: .competition, sport: .soccer, name: "FIFA WC African Qualifiers", country: "Africa"),
        .init(kind: .competition, sport: .soccer, name: "FIFA WC Asian Qualifiers", country: "Asia"),
        .init(kind: .competition, sport: .soccer, name: "FIFA WC Oceanian Qualifiers", country: "Oceania"),
    ]

    private let cricketTeams: [FavoriteCatalogItem] = [
        .init(kind: .team, sport: .cricket, name: "India", country: "India"),
        .init(kind: .team, sport: .cricket, name: "Australia", country: "Australia"),
        .init(kind: .team, sport: .cricket, name: "England", country: "England"),
        .init(kind: .team, sport: .cricket, name: "Pakistan", country: "Pakistan"),
        .init(kind: .team, sport: .cricket, name: "South Africa", country: "South Africa"),
        .init(kind: .team, sport: .cricket, name: "New Zealand", country: "New Zealand"),
        .init(kind: .team, sport: .cricket, name: "Sri Lanka", country: "Sri Lanka"),
        .init(kind: .team, sport: .cricket, name: "Bangladesh", country: "Bangladesh"),
        .init(kind: .team, sport: .cricket, name: "West Indies", country: "West Indies"),
        .init(kind: .team, sport: .cricket, name: "Afghanistan", country: "Afghanistan"),
        .init(kind: .team, sport: .cricket, name: "Mumbai Indians", country: "India"),
        .init(kind: .team, sport: .cricket, name: "Chennai Super Kings", country: "India"),
        .init(kind: .team, sport: .cricket, name: "Royal Challengers Bengaluru", country: "India"),
        .init(kind: .team, sport: .cricket, name: "Kolkata Knight Riders", country: "India"),
        .init(kind: .team, sport: .cricket, name: "Rajasthan Royals", country: "India"),
        .init(kind: .team, sport: .cricket, name: "Sunrisers Hyderabad", country: "India"),
        .init(kind: .team, sport: .cricket, name: "Lucknow Super Giants", country: "India"),
        .init(kind: .team, sport: .cricket, name: "Punjab Kings", country: "India"),
        .init(kind: .team, sport: .cricket, name: "Delhi Capitals", country: "India"),
        .init(kind: .team, sport: .cricket, name: "Gujarat Titans", country: "India"),
    ]

    private let cricketCompetitions: [FavoriteCatalogItem] = [
        .init(kind: .competition, sport: .cricket, name: "IPL", country: "India"),
        .init(kind: .competition, sport: .cricket, name: "ICC Cricket World Cup", country: "International"),
        .init(kind: .competition, sport: .cricket, name: "ICC T20 World Cup", country: "International"),
        .init(kind: .competition, sport: .cricket, name: "WTC", country: "International"),
        .init(kind: .competition, sport: .cricket, name: "BBL", country: "Australia"),
        .init(kind: .competition, sport: .cricket, name: "PSL", country: "Pakistan"),
        .init(kind: .competition, sport: .cricket, name: "CPL", country: "West Indies"),
        .init(kind: .competition, sport: .cricket, name: "The Hundred", country: "England"),
    ]

    private var selected: [FavoriteSelection] {
        FavoriteSelectionsStore.decode(from: favoriteSelectionsJSON)
    }

    private var selectedTeams: [FavoriteSelection] {
        selected.filter { $0.kind == .team }
    }

    private var selectedCompetitions: [FavoriteSelection] {
        selected.filter { $0.kind == .competition }
    }

    private var catalog: [FavoriteCatalogItem] {
        FavoriteSelectionsStore.dedupe(soccerCompetitions.map(\.selection) + soccerTeamCatalog.map(\.selection) + cricketTeams.map(\.selection) + cricketCompetitions.map(\.selection))
            .map { FavoriteCatalogItem(kind: $0.kind, sport: $0.sport, name: $0.name, country: $0.country) }
    }

    private var filteredCatalog: [FavoriteCatalogItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return catalog.filter { item in
            let matchesSport: Bool = {
                switch sportFilter {
                case .all: return true
                case .soccer: return item.sport == .soccer
                case .cricket: return item.sport == .cricket
                }
            }()

            let matchesKind: Bool = {
                switch kindFilter {
                case .all: return true
                case .team: return item.kind == .team
                case .competition: return item.kind == .competition
                case .country: return true
                }
            }()

            guard matchesSport && matchesKind else { return false }

            guard !q.isEmpty else { return true }

            let target = "\(item.name.lowercased()) \(item.country?.lowercased() ?? "") \(item.sport.rawValue) \(item.kind.rawValue)"

            if kindFilter == .country {
                return (item.country?.lowercased().contains(q) ?? false)
            }

            return target.contains(q)
        }
        .sorted { lhs, rhs in
            if lhs.kind != rhs.kind {
                return lhs.kind.rawValue < rhs.kind.rawValue
            }
            if lhs.sport != rhs.sport {
                return lhs.sport.rawValue < rhs.sport.rawValue
            }
            return lhs.name < rhs.name
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            Text("Streaming & Favorites")
                .font(.title2)
                .bold()

            Form {
                Section("IPTV") {
                    TextField("M3U playlist URL", text: $iptvM3UURL)
                        .textFieldStyle(.roundedBorder)

                    TextField("EPG URL (XMLTV)", text: $iptvEPGURL)
                        .textFieldStyle(.roundedBorder)

                    HStack(spacing: 8) {
                        if hasM3U && hasEPG {
                            Label("M3U + EPG configured", systemImage: "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundColor(.green)
                        } else {
                            Label("Add both M3U and EPG for Where to Watch", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                        Spacer()
                    }

                    HStack(spacing: 8) {
                        if iptvEPGURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Button("Use Default Local EPG URL") {
                                iptvEPGURL = "http://192.168.1.20:7066/api/playlists/1/epg"
                            }
                            .buttonStyle(.bordered)
                        }

                        Button("Autofill EPG from M3U") {
                            if let inferred = inferEPGURL(from: iptvM3UURL) {
                                iptvEPGURL = inferred
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(!hasM3U)
                    }

                    Text("Live/upcoming match details use M3U + EPG to smart-match sports channels for Where to Watch.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("Streamed Provider") {
                    TextField("Streamed API base URL", text: $streamedBaseURL)
                        .textFieldStyle(.roundedBorder)

                    Label("Always enabled as primary stream source", systemImage: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundColor(.green)

                    Text("Matcha queries Streamed first and falls back to IPTV channels when needed.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("Selected Favorites") {
                    if selected.isEmpty {
                        Text("No favorites selected yet.")
                            .foregroundColor(.secondary)
                    }

                    if !selectedTeams.isEmpty {
                        favoritePills(title: "Teams", items: selectedTeams)
                    }

                    if !selectedCompetitions.isEmpty {
                        favoritePills(title: "Competitions", items: selectedCompetitions)
                    }
                }

                Section("Find and Add") {
                    HStack {
                        TextField("Search by team, competition, country, or sport", text: $query)
                            .textFieldStyle(.roundedBorder)

                        if isLoadingSoccerTeams {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }

                    HStack {
                        Picker("Type", selection: $kindFilter) {
                            ForEach(SearchKindFilter.allCases) { kind in
                                Text(kind.rawValue).tag(kind)
                            }
                        }

                        Picker("Sport", selection: $sportFilter) {
                            ForEach(SearchSportFilter.allCases) { sport in
                                Text(sport.rawValue).tag(sport)
                            }
                        }
                    }

                    List(filteredCatalog.prefix(150), id: \.id) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                Text("\(item.sport.rawValue.capitalized) • \(item.kind.rawValue.capitalized)\(item.country.map { " • \($0)" } ?? "")")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            if isSelected(item) {
                                Button("Selected") {
                                    remove(item)
                                }
                                .buttonStyle(.bordered)
                            } else {
                                Button("Add") {
                                    add(item)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                    }
                    .frame(minHeight: 240, maxHeight: 320)
                }

                Section("Legacy Import") {
                    Text("CSV favorites are no longer required. Use this once if you want to migrate old CSV values into searchable selections.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button("Import Existing CSV Favorites") {
                        importLegacyCSVIntoSelections()
                    }

                    Button("Clear Legacy CSV Values") {
                        legacyFavoriteSoccerCsv = ""
                        legacyFavoriteCricketCsv = ""
                        legacyFavoriteCompetitionsCsv = ""
                        legacyFavoriteTeamsCsv = ""
                    }
                }
            }
            .formStyle(.grouped)
        }
        .task {
            if !enableStreamedProvider {
                enableStreamedProvider = true
            }
            await loadSoccerTeamCatalogIfNeeded()
        }
        .onChange(of: iptvM3UURL) { newValue in
            if !hasEPG, let inferred = inferEPGURL(from: newValue) {
                iptvEPGURL = inferred
            }
        }
    }

    private func inferEPGURL(from m3uURL: String) -> String? {
        let trimmed = m3uURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard URL(string: trimmed) != nil else { return nil }

        if trimmed.contains("/m3u") {
            return trimmed.replacingOccurrences(of: "/m3u", with: "/epg")
        }
        if trimmed.lowercased().hasSuffix(".m3u") {
            return String(trimmed.dropLast(4)) + "/epg"
        }
        return nil
    }

    @ViewBuilder
    private func favoritePills(title: String, items: [FavoriteSelection]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 8)], spacing: 8) {
                ForEach(items, id: \.id) { item in
                    HStack(spacing: 6) {
                        Text(item.name)
                            .font(.caption)
                            .lineLimit(1)

                        Spacer(minLength: 0)

                        Button {
                            removeSelection(withID: item.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                }
            }
        }
    }

    private func add(_ item: FavoriteCatalogItem) {
        var current = selected
        current.append(item.selection)
        favoriteSelectionsJSON = FavoriteSelectionsStore.encode(current)
    }

    private func remove(_ item: FavoriteCatalogItem) {
        removeSelection(withID: item.id)
    }

    private func removeSelection(withID id: String) {
        let remaining = selected.filter { $0.id != id }
        favoriteSelectionsJSON = FavoriteSelectionsStore.encode(remaining)
    }

    private func isSelected(_ item: FavoriteCatalogItem) -> Bool {
        selected.contains(where: { $0.id == item.id })
    }

    private func loadSoccerTeamCatalogIfNeeded() async {
        guard !loadedSoccerTeams else { return }

        loadedSoccerTeams = true
        isLoadingSoccerTeams = true
        defer { isLoadingSoccerTeams = false }

        let leagueCountry: [(code: String, country: String)] = [
            ("MLS", "United States"),
            ("NWSL", "United States"),
            ("EPL", "England"),
            ("UEFA", "Europe"),
            ("EUEFA", "Europe"),
            ("ESP", "Spain"),
            ("GER", "Germany"),
            ("ITA", "Italy"),
            ("FRA", "France"),
            ("NED", "Netherlands"),
            ("POR", "Portugal"),
            ("MEX", "Mexico"),
        ]

        var collected: [FavoriteCatalogItem] = []

        for league in leagueCountry {
            guard let standings = await SoccerStandingsService.shared.topStandings(for: league.code, maxRows: 40) else {
                continue
            }

            for row in standings.rows {
                collected.append(
                    .init(kind: .team, sport: .soccer, name: row.teamName, country: league.country)
                )
            }
        }

        let unique = FavoriteSelectionsStore.dedupe(collected.map(\.selection))
            .map { FavoriteCatalogItem(kind: $0.kind, sport: $0.sport, name: $0.name, country: $0.country) }

        soccerTeamCatalog = unique
    }

    private func importLegacyCSVIntoSelections() {
        var current = selected

        let soccerTerms = (legacyFavoriteSoccerCsv + "," + legacyFavoriteTeamsCsv)
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let cricketTerms = (legacyFavoriteCricketCsv + "," + legacyFavoriteTeamsCsv)
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let competitionTerms = legacyFavoriteCompetitionsCsv
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for value in soccerTerms {
            current.append(.init(kind: .team, sport: .soccer, name: value, country: nil))
        }
        for value in cricketTerms {
            current.append(.init(kind: .team, sport: .cricket, name: value, country: nil))
        }
        for value in competitionTerms {
            current.append(.init(kind: .competition, sport: .soccer, name: value, country: nil))
            current.append(.init(kind: .competition, sport: .cricket, name: value, country: nil))
        }

        favoriteSelectionsJSON = FavoriteSelectionsStore.encode(current)
    }
}
