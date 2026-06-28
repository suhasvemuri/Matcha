import Foundation

enum FavoriteKind: String, Codable, CaseIterable {
    case team
    case competition
}

enum FavoriteSport: String, Codable, CaseIterable {
    case soccer
    case cricket
}

struct FavoriteSelection: Codable, Hashable, Identifiable {
    let kind: FavoriteKind
    let sport: FavoriteSport
    let name: String
    let country: String?

    var id: String {
        "\(kind.rawValue)|\(sport.rawValue)|\(name.lowercased())"
    }
}

enum FavoriteSelectionsStore {
    static let storageKey = "favoriteSelectionsJSON"

    static func decode(from json: String) -> [FavoriteSelection] {
        guard !json.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([FavoriteSelection].self, from: data)
        else {
            return []
        }

        return decoded
    }

    static func encode(_ items: [FavoriteSelection]) -> String {
        let unique = dedupe(items)
        guard let data = try? JSONEncoder().encode(unique),
              let json = String(data: data, encoding: .utf8)
        else {
            return ""
        }

        return json
    }

    static func dedupe(_ items: [FavoriteSelection]) -> [FavoriteSelection] {
        var seen = Set<String>()
        var ordered: [FavoriteSelection] = []

        for item in items {
            if !seen.contains(item.id) {
                ordered.append(item)
                seen.insert(item.id)
            }
        }

        return ordered
    }

    static func teamTerms(json: String, legacySoccerCsv: String, legacyCricketCsv: String, legacyCombinedCsv: String) -> [String] {
        let newTeams = decode(from: json)
            .filter { $0.kind == .team }
            .map { $0.name.lowercased() }

        if !newTeams.isEmpty {
            return Array(Set(newTeams)).sorted()
        }

        let csv = [legacySoccerCsv, legacyCricketCsv, legacyCombinedCsv]
            .joined(separator: ",")

        return csv
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }

    static func teamTerms(json: String, sport: FavoriteSport, legacySoccerCsv: String, legacyCricketCsv: String, legacyCombinedCsv: String) -> [String] {
        let newTeams = decode(from: json)
            .filter { $0.kind == .team && $0.sport == sport }
            .map { $0.name.lowercased() }

        if !newTeams.isEmpty {
            return Array(Set(newTeams)).sorted()
        }

        let csv: String
        switch sport {
        case .soccer:
            csv = [legacySoccerCsv, legacyCombinedCsv].joined(separator: ",")
        case .cricket:
            csv = [legacyCricketCsv, legacyCombinedCsv].joined(separator: ",")
        }

        return csv
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }

    static func competitionTerms(json: String, legacyCsv: String) -> [String] {
        let newCompetitions = decode(from: json)
            .filter { $0.kind == .competition }
            .map { $0.name.lowercased() }

        if !newCompetitions.isEmpty {
            return Array(Set(newCompetitions)).sorted()
        }

        return legacyCsv
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }

    /// Maps a favoritable competition (by lowercased catalog name) to the
    /// `@AppStorage` flag that gates its ESPN feed fetch. Favoriting a
    /// competition is meaningless unless its feed is actually fetched, so we
    /// keep these in sync. Cricket competitions all flow through the single
    /// `enableCricket` feed.
    static let competitionFeedEnableKeys: [String: String] = [
        // Soccer leagues
        "mls": "enableMLS",
        "nwsl": "enableNWSL",
        "premier league": "enableEPL",
        "uefa champions league": "enableUEFA",
        "uefa europa league": "enableEUEFA",
        "la liga": "enableESP",
        "bundesliga": "enableGER",
        "serie a": "enableITA",
        "ligue 1": "enableFRA",
        "eredivisie": "enableNED",
        "primeira liga": "enablePOR",
        "liga mx": "enableMEX",
        // FIFA World Cup family
        "fifa world cup": "enableFFWC",
        "fifa women's world cup": "enableFFWWC",
        "fifa wc uefa qualifiers": "enableFFWCQUEFA",
        "fifa wc conmebol qualifiers": "enableCONMEBOL",
        "fifa wc concacaf qualifiers": "enableCONCACAF",
        "fifa wc african qualifiers": "enableCAF",
        "fifa wc asian qualifiers": "enableAFC",
        "fifa wc oceanian qualifiers": "enableOFC",
        // Cricket (single shared feed)
        "ipl": "enableCricket",
        "icc cricket world cup": "enableCricket",
        "icc t20 world cup": "enableCricket",
        "wtc": "enableCricket",
        "bbl": "enableCricket",
        "psl": "enableCricket",
        "cpl": "enableCricket",
        "the hundred": "enableCricket",
    ]

    /// Enables every feed required by the user's favorite competitions so the
    /// matches they picked actually get fetched. Returns the set of keys it
    /// switched on (useful for logging/tests). Never disables anything.
    @discardableResult
    static func syncFeedEnables(from json: String, defaults: UserDefaults = .standard) -> [String] {
        let favoritedCompetitions = decode(from: json)
            .filter { $0.kind == .competition }
            .map { $0.name.lowercased() }

        var switchedOn: [String] = []
        for name in favoritedCompetitions {
            guard let key = competitionFeedEnableKeys[name] else { continue }
            if !defaults.bool(forKey: key) {
                defaults.set(true, forKey: key)
                switchedOn.append(key)
            }
        }
        return switchedOn
    }
}

struct FavoriteCatalogItem: Identifiable, Hashable {
    let kind: FavoriteKind
    let sport: FavoriteSport
    let name: String
    let country: String?

    var id: String {
        "\(kind.rawValue)|\(sport.rawValue)|\(name.lowercased())"
    }

    var selection: FavoriteSelection {
        FavoriteSelection(kind: kind, sport: sport, name: name, country: country)
    }
}

enum FavoriteCatalogProvider {
    static let soccerCompetitions: [FavoriteCatalogItem] = [
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

    static let cricketTeams: [FavoriteCatalogItem] = [
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

    static let cricketCompetitions: [FavoriteCatalogItem] = [
        .init(kind: .competition, sport: .cricket, name: "IPL", country: "India"),
        .init(kind: .competition, sport: .cricket, name: "ICC Cricket World Cup", country: "International"),
        .init(kind: .competition, sport: .cricket, name: "ICC T20 World Cup", country: "International"),
        .init(kind: .competition, sport: .cricket, name: "WTC", country: "International"),
        .init(kind: .competition, sport: .cricket, name: "BBL", country: "Australia"),
        .init(kind: .competition, sport: .cricket, name: "PSL", country: "Pakistan"),
        .init(kind: .competition, sport: .cricket, name: "CPL", country: "West Indies"),
        .init(kind: .competition, sport: .cricket, name: "The Hundred", country: "England"),
    ]

    /// National teams (World Cup family). Club standings don't include these, so
    /// list them explicitly — this is what lets a user follow the World Cup but
    /// filter it to selected countries. Names match CountryFlags so flags render.
    static let soccerNationalTeams: [FavoriteCatalogItem] = [
        // UEFA
        n("England"), n("Spain"), n("France"), n("Germany"), n("Italy"),
        n("Portugal"), n("Netherlands"), n("Belgium"), n("Croatia"), n("Serbia"),
        n("Switzerland"), n("Denmark"), n("Poland"), n("Austria"), n("Ukraine"),
        n("Sweden"), n("Norway"), n("Turkey"), n("Scotland"), n("Wales"),
        // CONMEBOL
        n("Brazil"), n("Argentina"), n("Uruguay"), n("Colombia"), n("Chile"),
        n("Peru"), n("Ecuador"), n("Paraguay"), n("Bolivia"), n("Venezuela"),
        // CONCACAF
        n("United States"), n("Mexico"), n("Canada"), n("Costa Rica"), n("Panama"),
        n("Jamaica"), n("Honduras"),
        // CAF
        n("Morocco"), n("Senegal"), n("Ivory Coast"), n("Nigeria"), n("Ghana"),
        n("Cameroon"), n("Egypt"), n("Algeria"), n("Tunisia"), n("South Africa"),
        n("Mali"), n("Cape Verde"),
        // AFC
        n("Japan"), n("South Korea"), n("Iran"), n("Saudi Arabia"), n("Australia"),
        n("Qatar"), n("Iraq"), n("Uzbekistan"), n("Jordan"),
        // OFC
        n("New Zealand"),
    ]

    private static func n(_ name: String) -> FavoriteCatalogItem {
        .init(kind: .team, sport: .soccer, name: name, country: "International")
    }

    static let quickStartPicks: [FavoriteCatalogItem] = [
        .init(kind: .competition, sport: .cricket, name: "IPL", country: "India"),
        .init(kind: .competition, sport: .cricket, name: "ICC T20 World Cup", country: "International"),
        .init(kind: .team, sport: .cricket, name: "India", country: "India"),
        .init(kind: .team, sport: .cricket, name: "Australia", country: "Australia"),
        .init(kind: .competition, sport: .soccer, name: "Premier League", country: "England"),
        .init(kind: .competition, sport: .soccer, name: "UEFA Champions League", country: "Europe"),
        .init(kind: .competition, sport: .soccer, name: "La Liga", country: "Spain"),
        .init(kind: .competition, sport: .soccer, name: "FIFA World Cup", country: "International"),
    ]

    static func allStaticItems() -> [FavoriteCatalogItem] {
        dedupe(soccerCompetitions + soccerNationalTeams + cricketTeams + cricketCompetitions)
    }

    static func loadSoccerTeamCatalog() async -> [FavoriteCatalogItem] {
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
                collected.append(.init(kind: .team, sport: .soccer, name: row.teamName, country: league.country))
            }
        }

        return dedupe(collected)
    }

    static func dedupe(_ items: [FavoriteCatalogItem]) -> [FavoriteCatalogItem] {
        FavoriteSelectionsStore.dedupe(items.map(\.selection))
            .map { FavoriteCatalogItem(kind: $0.kind, sport: $0.sport, name: $0.name, country: $0.country) }
    }
}
