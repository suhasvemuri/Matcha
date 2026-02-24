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
