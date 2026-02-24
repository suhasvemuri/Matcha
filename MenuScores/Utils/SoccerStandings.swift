import Foundation

struct SoccerStandingRow: Identifiable {
    let id: String
    let rank: String
    let teamName: String
    let points: String
    let played: String
    let record: String
}

actor SoccerStandingsService {
    static let shared = SoccerStandingsService()

    private struct CacheItem {
        let title: String
        let rows: [SoccerStandingRow]
        let loadedAt: Date
    }

    private var cache: [String: CacheItem] = [:]

    func topStandings(for league: String, maxRows: Int = 5) async -> (title: String, rows: [SoccerStandingRow])? {
        if let cached = cache[league], Date().timeIntervalSince(cached.loadedAt) < 900 {
            return (cached.title, Array(cached.rows.prefix(maxRows)))
        }

        guard let url = LeagueLinks.standingsAPIURL(for: league) else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
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
            print("Failed to fetch standings:", error)
            return nil
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
