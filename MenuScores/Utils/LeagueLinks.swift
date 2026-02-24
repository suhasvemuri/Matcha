import Foundation

enum LeagueLinks {
    static func standingsSlug(for league: String) -> String? {
        switch league.uppercased() {
        case "MLS": return "usa.1"
        case "NWSL": return "usa.nwsl"
        case "UEFA": return "uefa.champions"
        case "EUEFA": return "uefa.europa"
        case "WUEFA": return "uefa.wchampions"
        case "WEPL": return "eng.w.1"
        case "EPL": return "eng.1"
        case "ESP": return "esp.1"
        case "GER": return "ger.1"
        case "ITA": return "ita.1"
        case "MEX": return "mex.1"
        case "FRA": return "fra.1"
        case "NED": return "ned.1"
        case "POR": return "por.1"
        default: return nil
        }
    }

    static func standingsAPIURL(for league: String) -> URL? {
        guard let slug = standingsSlug(for: league) else { return nil }
        return URL(string: "https://site.web.api.espn.com/apis/v2/sports/soccer/\(slug)/standings")
    }

    static func standingsURL(for league: String) -> URL? {
        if let slug = standingsSlug(for: league) {
            return URL(string: "https://www.espn.com/soccer/standings/_/league/\(slug)")
        }

        switch league.uppercased() {
        case "FFWC": return URL(string: "https://www.fifa.com/en/tournaments/mens/worldcup")
        case "FFWWC": return URL(string: "https://www.fifa.com/en/tournaments/womens/womensworldcup")
        case "FFWCQUEFA": return URL(string: "https://www.uefa.com/european-qualifiers/standings/")
        case "CONMEBOL": return URL(string: "https://www.conmebol.com/en/world-cup-qualifiers")
        case "CONCACAF": return URL(string: "https://www.concacaf.com/world-cup-qualifying-men/")
        case "CAF": return URL(string: "https://www.cafonline.com/caf-world-cup-qualifiers/")
        case "AFC": return URL(string: "https://www.the-afc.com/en/national/fifa_world_cup_2026.html")
        case "OFC": return URL(string: "https://www.oceaniafootball.com/")
        default: return nil
        }
    }

    static func liveSoccerTVSearchURL(for game: Event) -> URL? {
        guard let competition = game.competitions.first,
              let competitors = competition.competitors,
              competitors.count >= 2
        else { return nil }

        let away = competitors[1].team?.displayName ?? competitors[1].team?.name ?? ""
        let home = competitors[0].team?.displayName ?? competitors[0].team?.name ?? ""
        let rawQuery = "\(away) vs \(home)"
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "+")

        guard !rawQuery.isEmpty else { return nil }
        return URL(string: "https://www.livesoccertv.com/search/?q=\(rawQuery)")
    }
}
