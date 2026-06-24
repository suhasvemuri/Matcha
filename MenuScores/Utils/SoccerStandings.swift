import Foundation

struct SoccerStandingRow: Identifiable {
    let id: String
    let rank: String
    let teamName: String
    let points: String
    let played: String
    let record: String
}

struct SoccerStandingGroup: Identifiable {
    let id: String
    let name: String
    let rows: [SoccerStandingRow]
}

actor SoccerStandingsService {
    static let shared = SoccerStandingsService()

    private struct CacheItem {
        let title: String
        let rows: [SoccerStandingRow]
        let loadedAt: Date
    }

    private var cache: [String: CacheItem] = [:]
    private var groupCache: [String: (groups: [SoccerStandingGroup], loadedAt: Date)] = [:]

    func topStandings(for league: String, maxRows: Int = 5) async -> (title: String, rows: [SoccerStandingRow])? {
        if let cached = cache[league], Date().timeIntervalSince(cached.loadedAt) < 900 {
            return (cached.title, Array(cached.rows.prefix(maxRows)))
        }

        guard let url = LeagueLinks.standingsAPIURL(for: league) else { return nil }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw NetworkError.invalidResponse
            }

            let decoded = try JSONDecoder().decode(SoccerStandingsResponse.self, from: data)
            guard let child = decoded.children?.first else { return nil }

            let rows = child.standings.entries.map { entry in
                let rank = entry.value(for: "rank")
                let points = entry.value(for: "points")
                let played = entry.value(for: "gamesPlayed")
                let wins = entry.value(for: "wins")
                let draws = entry.value(for: "ties")
                let losses = entry.value(for: "losses")

                return SoccerStandingRow(
                    id: entry.team.id,
                    rank: rank,
                    teamName: entry.team.shortDisplayName ?? entry.team.displayName,
                    points: points,
                    played: played,
                    record: "\(wins)-\(draws)-\(losses)"
                )
            }

            let item = CacheItem(
                title: child.name ?? decoded.name ?? "Standings",
                rows: rows,
                loadedAt: Date()
            )
            cache[league] = item

            return (item.title, Array(item.rows.prefix(maxRows)))
        } catch {
            Log.feed.error("Failed to fetch standings: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// All group tables for a competition (e.g. the World Cup's Groups A–L).
    /// Single-table leagues come back as one group.
    func groupStandings(for league: String) async -> [SoccerStandingGroup]? {
        if let cached = groupCache[league], Date().timeIntervalSince(cached.loadedAt) < 900 {
            return cached.groups
        }

        guard let url = LeagueLinks.standingsAPIURL(for: league) else { return nil }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw NetworkError.invalidResponse
            }

            let decoded = try JSONDecoder().decode(SoccerStandingsResponse.self, from: data)
            guard let children = decoded.children, !children.isEmpty else { return nil }

            let groups = children.enumerated().map { index, child in
                SoccerStandingGroup(
                    id: "\(index)",
                    name: child.name ?? "Group \(index + 1)",
                    rows: Self.rows(from: child)
                )
            }

            groupCache[league] = (groups, Date())
            return groups
        } catch {
            Log.feed.error("Failed to fetch group standings: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func rows(from child: SoccerStandingsChild) -> [SoccerStandingRow] {
        child.standings.entries.map { entry in
            SoccerStandingRow(
                id: entry.team.id,
                rank: entry.value(for: "rank"),
                teamName: entry.team.shortDisplayName ?? entry.team.displayName,
                points: entry.value(for: "points"),
                played: entry.value(for: "gamesPlayed"),
                record: "\(entry.value(for: "wins"))-\(entry.value(for: "ties"))-\(entry.value(for: "losses"))"
            )
        }
    }
}

private struct SoccerStandingsResponse: Decodable {
    let name: String?
    let children: [SoccerStandingsChild]?
}

private struct SoccerStandingsChild: Decodable {
    let name: String?
    let standings: SoccerStandings
}

private struct SoccerStandings: Decodable {
    let entries: [SoccerStandingEntry]
}

private struct SoccerStandingEntry: Decodable {
    let team: SoccerStandingTeam
    let stats: [SoccerStandingStat]

    func value(for key: String) -> String {
        stats.first(where: { $0.name == key })?.displayValue ?? "-"
    }
}

private struct SoccerStandingTeam: Decodable {
    let id: String
    let displayName: String
    let shortDisplayName: String?
}

private struct SoccerStandingStat: Decodable {
    let name: String
    let displayValue: String
}
