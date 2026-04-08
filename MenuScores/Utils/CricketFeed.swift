import Foundation

struct CricketInning: Equatable {
    let number: Int
    let runs: Int
    let wickets: Int?
    let overs: Double?

    var line: String {
        var text = "\(runs)"
        if let wickets {
            text += "/\(wickets)"
        }
        if let overs {
            if overs.rounded(.towardZero) == overs {
                text += " (\(Int(overs)))"
            } else {
                text += " (\(String(format: "%.1f", overs)))"
            }
        }
        return text
    }
}

struct CricketBatterLine: Identifiable, Equatable {
    let id: String
    let name: String
    let runs: Int
    let balls: Int
    let fours: Int
    let sixes: Int
    let strikeRate: Double
    let outDescription: String
}

struct CricketBowlerLine: Identifiable, Equatable {
    let id: String
    let name: String
    let overs: Double
    let maidens: Int
    let runs: Int
    let wickets: Int
    let economy: Double
}

struct CricketInningsBreakdown: Identifiable, Equatable {
    struct ExtrasBreakdown: Equatable {
        let byes: Int
        let legByes: Int
        let wides: Int
        let noBalls: Int
        let total: Int

        var line: String {
            "B \(byes) • LB \(legByes) • WD \(wides) • NB \(noBalls) • Total \(total)"
        }
    }

    struct PartnershipLine: Identifiable, Equatable {
        let id: String
        let batter1: String
        let batter2: String
        let runs: Int
        let balls: Int

        var line: String {
            "\(batter1)/\(batter2) \(runs) (\(balls)b)"
        }
    }

    let id: String
    let inningsNumber: Int
    let battingTeamShort: String
    let bowlingTeamShort: String
    let totalRuns: Int
    let wickets: Int
    let overs: Double
    let runRate: Double
    let extras: ExtrasBreakdown
    let powerplaySummary: String
    let fallOfWickets: [String]
    let partnerships: [PartnershipLine]
    let yetToBat: [String]
    let batters: [CricketBatterLine]
    let bowlers: [CricketBowlerLine]

    var topBatters: [CricketBatterLine] {
        Array(batters.prefix(5))
    }

    var topBowlers: [CricketBowlerLine] {
        Array(bowlers.prefix(4))
    }

    var totalLine: String {
        let oversText: String
        if overs.rounded(.towardZero) == overs {
            oversText = "\(Int(overs))"
        } else {
            oversText = String(format: "%.1f", overs)
        }
        return "\(battingTeamShort) \(totalRuns)/\(wickets) (\(oversText) ov)"
    }
}

struct CricketScorecardSummary: Equatable {
    let innings: [CricketInningsBreakdown]
    let pointsTableURL: URL?
    let venue: String?
    let toss: String?
    let playerOfMatch: String?
}

struct CricketStandingRow: Identifiable, Equatable {
    let id: String
    let rank: Int
    let teamName: String
    let teamShort: String?
    let teamLogoURL: URL?
    let played: Int
    let won: Int
    let lost: Int
    let points: Int
    let nrr: String
}

struct CricketStandingGroup: Identifiable, Equatable {
    let id: String
    let name: String
    let rows: [CricketStandingRow]
}

struct CricketStandingsTable: Equatable {
    let groups: [CricketStandingGroup]
}

struct CricketMatch: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let url: URL

    let team1Name: String
    let team2Name: String
    let team1Short: String
    let team2Short: String
    let team1Score: String
    let team2Score: String
    let team1InningsDetail: [CricketInning]
    let team2InningsDetail: [CricketInning]
    let team1Innings: [String]
    let team2Innings: [String]
    let state: String
    let status: String
    let seriesName: String
    let matchDesc: String
    let startTimestamp: Int64

    var isLive: Bool {
        let s = state.lowercased()
        return s.contains("live") || s.contains("in progress") || s == "innings break"
    }

    var isUpcoming: Bool {
        let s = state.lowercased()
        return s.contains("preview") || s.contains("upcoming") || s.contains("scheduled")
    }

    var scoreLine: String {
        if !team1Score.isEmpty || !team2Score.isEmpty {
            return "\(team1Short) \(team1Score.isEmpty ? "-" : team1Score) - \(team2Short) \(team2Score.isEmpty ? "-" : team2Score)"
        }
        return "\(team1Short) vs \(team2Short)"
    }

    var menubarText: String {
        if isLive {
            if let context = conciseLiveContext {
                return "\(scoreLine) • \(context)"
            }
            return scoreLine
        }
        if isUpcoming {
            return "\(team1Short) vs \(team2Short) - \(matchDesc)"
        }
        if !status.isEmpty {
            return "\(scoreLine)  \(status)"
        }
        return scoreLine
    }

    var conciseLiveContext: String? {
        let candidates = [status, detail, matchDesc]
        for raw in candidates {
            let cleaned = raw
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { continue }
            let lower = cleaned.lowercased()

            // Skip noisy toss-only context for menu bar pin text.
            if lower.contains("opt to bowl")
                || lower.contains("opt to bat")
                || lower.contains("won the toss")
                || lower == "live"
                || lower == "in progress"
            {
                continue
            }

            return cleaned
        }
        return nil
    }
}

@MainActor
final class CricketListView: ObservableObject {
    @Published var matches: [CricketMatch] = []

    func populateMatches() async {
        do {
            self.matches = try await CricketFeed.fetchMatches()
        } catch {
            print("Failed to fetch cricket matches:", error)
        }
    }
}

enum CricketFeed {
    private static let liveScoresURL = URL(string: "https://www.cricbuzz.com/cricket-match/live-scores")!
    private static let scorecardBaseURL = URL(string: "https://www.cricbuzz.com/live-cricket-scorecard/")!
    private static let baseURL = URL(string: "https://www.cricbuzz.com")!

    static func fetchMatches() async throws -> [CricketMatch] {
        var request = URLRequest(url: liveScoresURL)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NetworkError.invalidResponse
        }

        guard let html = String(data: data, encoding: .utf8) else {
            return []
        }

        return parseMatches(from: html)
    }

    static func parseMatches(from html: String) -> [CricketMatch] {
        let anchorMap = parseAnchorMap(from: html)
        let escapedObjects = extractEscapedMatchObjects(from: html)

        var seen = Set<String>()
        var result: [CricketMatch] = []

        for rawObject in escapedObjects {
            guard let object = decodeEscapedJSONObject(rawObject),
                  let matchInfo = object["matchInfo"] as? [String: Any],
                  let matchIDNumber = matchInfo["matchId"] as? NSNumber
            else { continue }

            let matchID = "\(matchIDNumber.intValue)"
            guard !seen.contains(matchID) else { continue }
            seen.insert(matchID)

            let team1 = matchInfo["team1"] as? [String: Any]
            let team2 = matchInfo["team2"] as? [String: Any]

            let team1Name = (team1?["teamName"] as? String) ?? "Team 1"
            let team2Name = (team2?["teamName"] as? String) ?? "Team 2"
            let team1Short = (team1?["teamSName"] as? String) ?? String(team1Name.prefix(3)).uppercased()
            let team2Short = (team2?["teamSName"] as? String) ?? String(team2Name.prefix(3)).uppercased()

            let state = (matchInfo["state"] as? String) ?? ""
            let status = (matchInfo["status"] as? String) ?? ""
            let seriesName = (matchInfo["seriesName"] as? String) ?? ""
            let matchDesc = (matchInfo["matchDesc"] as? String) ?? ""
            let startTimestamp = (matchInfo["startDate"] as? NSNumber)?.int64Value ?? 0

            let matchScore = object["matchScore"] as? [String: Any]
            let team1ScoreData = formatTeamScore(matchScore?["team1Score"] as? [String: Any])
            let team2ScoreData = formatTeamScore(matchScore?["team2Score"] as? [String: Any])

            let mapped = anchorMap[matchIDNumber.intValue]
            let fallbackTitle = "\(team1Name) vs \(team2Name)"

            let title = mapped?.title ?? fallbackTitle
            let detail = mapped?.detail ?? (status.isEmpty ? matchDesc : status)
            let url = mapped?.url ?? liveScoresURL

            result.append(
                CricketMatch(
                    id: matchID,
                    title: title,
                    detail: detail,
                    url: url,
                    team1Name: team1Name,
                    team2Name: team2Name,
                    team1Short: team1Short,
                    team2Short: team2Short,
                    team1Score: team1ScoreData.summary,
                    team2Score: team2ScoreData.summary,
                    team1InningsDetail: team1ScoreData.details,
                    team2InningsDetail: team2ScoreData.details,
                    team1Innings: team1ScoreData.innings,
                    team2Innings: team2ScoreData.innings,
                    state: state,
                    status: status,
                    seriesName: seriesName,
                    matchDesc: matchDesc,
                    startTimestamp: startTimestamp
                )
            )
        }

        return result.sorted { lhs, rhs in
            lhs.startTimestamp < rhs.startTimestamp
        }
    }

    static func fetchScorecardSummary(matchID: String) async -> CricketScorecardSummary? {
        guard let url = URL(string: matchID, relativeTo: scorecardBaseURL)?.absoluteURL else {
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }
            guard let html = String(data: data, encoding: .utf8) else {
                return nil
            }
            return parseScorecardSummary(from: html)
        } catch {
            return nil
        }
    }

    static func fetchPointsTableURL(matchID: String) async -> URL? {
        guard let url = URL(string: matchID, relativeTo: scorecardBaseURL)?.absoluteURL else {
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }
            guard let html = String(data: data, encoding: .utf8) else {
                return nil
            }
            return extractPointsTableURL(from: html) ?? extractSeriesPointsTableURL(from: html)
        } catch {
            return nil
        }
    }

    static func fetchStandings(from pointsTableURL: URL) async -> CricketStandingsTable? {
        var request = URLRequest(url: pointsTableURL)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }
            guard let html = String(data: data, encoding: .utf8) else {
                return nil
            }
            return parseStandings(from: html)
        } catch {
            return nil
        }
    }

    private static func parseAnchorMap(from html: String) -> [Int: (url: URL, title: String, detail: String)] {
        let pattern = #"<a href="(/live-cricket-scores/([^/]+)/[^"]+)"[^>]*title="([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return [:]
        }

        let nsRange = NSRange(html.startIndex..., in: html)
        let matches = regex.matches(in: html, range: nsRange)

        var map: [Int: (url: URL, title: String, detail: String)] = [:]

        for match in matches {
            guard match.numberOfRanges > 3,
                  let pathRange = Range(match.range(at: 1), in: html),
                  let idRange = Range(match.range(at: 2), in: html),
                  let titleRange = Range(match.range(at: 3), in: html),
                  let matchID = Int(html[idRange]),
                  let url = URL(string: String(html[pathRange]), relativeTo: baseURL)?.absoluteURL
            else { continue }

            let rawTitle = String(html[titleRange])
            let parts = rawTitle.components(separatedBy: " - ")
            let title = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? rawTitle
            let detail = parts.dropFirst().joined(separator: " - ").trimmingCharacters(in: .whitespacesAndNewlines)

            map[matchID] = (url, title, detail)
        }

        return map
    }

    private static func parseScorecardSummary(from html: String) -> CricketScorecardSummary? {
        let scoreCard: [[String: Any]] = {
            if let scorecardObject = extractJSONObject(afterToken: #""scorecardApiData":"#, in: html)
                ?? extractJSONObject(afterToken: #"\"scorecardApiData\":"#, in: html),
               let nested = scorecardObject["scoreCard"] as? [[String: Any]] {
                return nested
            }

            if let rawArray = extractJSONArray(afterToken: #""scoreCard":"#, in: html)
                ?? extractJSONArray(afterToken: #"\"scoreCard\":"#, in: html),
                      let nested = rawArray as? [[String: Any]] {
                return nested
            }

            return []
        }()

        let inningsBreakdown: [CricketInningsBreakdown] = scoreCard.compactMap { innings in
            guard let inningsNumber = (innings["inningsId"] as? NSNumber)?.intValue,
                  let batTeamDetails = innings["batTeamDetails"] as? [String: Any],
                  let bowlTeamDetails = innings["bowlTeamDetails"] as? [String: Any],
                  let scoreDetails = innings["scoreDetails"] as? [String: Any]
            else {
                return nil
            }

            let battingTeamShort = (batTeamDetails["batTeamShortName"] as? String) ?? "BAT"
            let bowlingTeamShort = (bowlTeamDetails["bowlTeamShortName"] as? String) ?? "BWL"

            let totalRuns = (scoreDetails["runs"] as? NSNumber)?.intValue ?? 0
            let wickets = (scoreDetails["wickets"] as? NSNumber)?.intValue ?? 0
            let overs = (scoreDetails["overs"] as? NSNumber)?.doubleValue ?? 0
            let runRate = (scoreDetails["runRate"] as? NSNumber)?.doubleValue ?? 0
            let extras = parseExtras(from: innings["extrasData"] as? [String: Any])
            let powerplaySummary = parsePowerplaySummary(from: innings["ppData"] as? [String: Any])
            let fallOfWickets = parseFallOfWickets(from: innings["wicketsData"] as? [String: Any])
            let partnerships = parsePartnerships(from: innings["partnershipsData"] as? [String: Any])
            let yetToBat = parseYetToBat(from: batTeamDetails)

            let batters = parseBatters(from: batTeamDetails)
            let bowlers = parseBowlers(from: bowlTeamDetails)

            return CricketInningsBreakdown(
                id: "inn-\(inningsNumber)-\(battingTeamShort)-\(bowlingTeamShort)",
                inningsNumber: inningsNumber,
                battingTeamShort: battingTeamShort,
                bowlingTeamShort: bowlingTeamShort,
                totalRuns: totalRuns,
                wickets: wickets,
                overs: overs,
                runRate: runRate,
                extras: extras,
                powerplaySummary: powerplaySummary,
                fallOfWickets: fallOfWickets,
                partnerships: partnerships,
                yetToBat: yetToBat,
                batters: batters,
                bowlers: bowlers
            )
        }

        let pointsURL = extractPointsTableURL(from: html) ?? extractSeriesPointsTableURL(from: html)
        let venue = extractVenue(from: html)
        let toss = extractLooseFact(label: "Toss", from: html)
        let playerOfMatch = extractPlayerOfMatch(from: html)

        if inningsBreakdown.isEmpty,
           pointsURL == nil,
           venue == nil,
           toss == nil,
           playerOfMatch == nil
        {
            return nil
        }

        return CricketScorecardSummary(
            innings: inningsBreakdown.sorted { $0.inningsNumber < $1.inningsNumber },
            pointsTableURL: pointsURL,
            venue: venue,
            toss: toss,
            playerOfMatch: playerOfMatch
        )
    }

    private static func parseStandings(from html: String) -> CricketStandingsTable? {
        let candidates = extractAllJSONArrays(afterToken: #""pointsTable":["#, in: html)
            + extractAllJSONArrays(afterToken: #"\"pointsTable\":["#, in: html)
            + extractLoosePointsTableArrays(from: html)

        for candidate in candidates {
            guard let groupsArray = candidate as? [[String: Any]] else { continue }
            let groups = parseStandingGroups(from: groupsArray)
            if !groups.isEmpty {
                return CricketStandingsTable(groups: groups)
            }
        }

        if let fallbackRows = parseLooseStandingRows(from: html), !fallbackRows.isEmpty {
            let group = CricketStandingGroup(id: "standings", name: "Standings", rows: fallbackRows)
            return CricketStandingsTable(groups: [group])
        }

        return nil
    }

    private static func parseStandingGroups(from groupsArray: [[String: Any]]) -> [CricketStandingGroup] {
        groupsArray.compactMap { group in
            let groupName = (group["groupName"] as? String) ?? "Standings"
            guard let rowsRaw = group["pointsTableInfo"] as? [[String: Any]], !rowsRaw.isEmpty else {
                return nil
            }

            let rows: [CricketStandingRow] = rowsRaw.enumerated().map { index, row in
                let team = (row["teamFullName"] as? String) ?? (row["teamName"] as? String) ?? "Team"
                let teamShort = (row["teamName"] as? String)
                    ?? (row["teamSName"] as? String)
                    ?? (row["teamShortName"] as? String)
                let teamLogoURL: URL? = {
                    let imageID = (row["teamImageId"] as? NSNumber)?.intValue
                        ?? (row["imageId"] as? NSNumber)?.intValue
                    guard let imageID else { return nil }
                    return URL(string: "https://static.cricbuzz.com/a/img/v1/25x18/i1/c\(imageID)/flag-img.jpg")
                }()
                let played = (row["matchesPlayed"] as? NSNumber)?.intValue ?? 0
                let won = (row["matchesWon"] as? NSNumber)?.intValue ?? 0
                let lost = (row["matchesLost"] as? NSNumber)?.intValue ?? 0
                let points = (row["points"] as? NSNumber)?.intValue ?? 0
                let nrr: String = {
                    if let value = row["nrr"] as? String { return value }
                    if let value = row["nrr"] as? NSNumber { return String(format: "%.3f", value.doubleValue) }
                    return "-"
                }()

                return CricketStandingRow(
                    id: "\(groupName)-\(team)-\(index)",
                    rank: index + 1,
                    teamName: team,
                    teamShort: teamShort,
                    teamLogoURL: teamLogoURL,
                    played: played,
                    won: won,
                    lost: lost,
                    points: points,
                    nrr: nrr
                )
            }

            return CricketStandingGroup(id: groupName, name: groupName, rows: rows)
        }
    }

    private static func parseBatters(from teamDetails: [String: Any]) -> [CricketBatterLine] {
        guard let batsmenData = teamDetails["batsmenData"] as? [String: Any] else {
            return []
        }

        let batters: [CricketBatterLine] = batsmenData.compactMap { key, value in
            guard let batter = value as? [String: Any] else { return nil }
            let name = (batter["batShortName"] as? String) ?? (batter["batName"] as? String) ?? key
            let runs = (batter["runs"] as? NSNumber)?.intValue ?? 0
            let balls = (batter["balls"] as? NSNumber)?.intValue ?? 0
            let fours = (batter["fours"] as? NSNumber)?.intValue ?? 0
            let sixes = (batter["sixes"] as? NSNumber)?.intValue ?? 0
            let strikeRate = (batter["strikeRate"] as? NSNumber)?.doubleValue ?? 0
            let outDescription = (batter["outDesc"] as? String) ?? ""

            if balls == 0 && runs == 0 && outDescription.isEmpty {
                return nil
            }

            return CricketBatterLine(
                id: key,
                name: name,
                runs: runs,
                balls: balls,
                fours: fours,
                sixes: sixes,
                strikeRate: strikeRate,
                outDescription: outDescription
            )
        }

        return batters.sorted { lhs, rhs in
            if lhs.runs != rhs.runs { return lhs.runs > rhs.runs }
            return lhs.balls < rhs.balls
        }
    }

    private static func parseBowlers(from teamDetails: [String: Any]) -> [CricketBowlerLine] {
        guard let bowlersData = teamDetails["bowlersData"] as? [String: Any] else {
            return []
        }

        let bowlers: [CricketBowlerLine] = bowlersData.compactMap { key, value in
            guard let bowler = value as? [String: Any] else { return nil }
            let name = (bowler["bowlShortName"] as? String) ?? (bowler["bowlName"] as? String) ?? key
            let overs = (bowler["overs"] as? NSNumber)?.doubleValue ?? 0
            let maidens = (bowler["maidens"] as? NSNumber)?.intValue ?? 0
            let runs = (bowler["runs"] as? NSNumber)?.intValue ?? 0
            let wickets = (bowler["wickets"] as? NSNumber)?.intValue ?? 0
            let economy = (bowler["economy"] as? NSNumber)?.doubleValue ?? 0

            if overs == 0 && wickets == 0 && runs == 0 {
                return nil
            }

            return CricketBowlerLine(
                id: key,
                name: name,
                overs: overs,
                maidens: maidens,
                runs: runs,
                wickets: wickets,
                economy: economy
            )
        }

        return bowlers.sorted { lhs, rhs in
            if lhs.wickets != rhs.wickets { return lhs.wickets > rhs.wickets }
            if lhs.economy != rhs.economy { return lhs.economy < rhs.economy }
            return lhs.runs < rhs.runs
        }
    }

    private static func parsePowerplaySummary(from powerplays: [String: Any]?) -> String {
        guard let powerplays else { return "" }

        let list: [String] = powerplays.compactMap { _, value in
            guard let pp = value as? [String: Any] else { return nil }
            let type = (pp["ppType"] as? String) ?? "PP"
            let from = (pp["ppOversFrom"] as? NSNumber)?.doubleValue ?? 0
            let to = (pp["ppOversTo"] as? NSNumber)?.doubleValue ?? 0
            let runs = (pp["runsScored"] as? NSNumber)?.intValue ?? 0
            return "\(type): \(runs) (\(formatOvers(from))-\(formatOvers(to)) ov)"
        }

        return list.joined(separator: " • ")
    }

    private static func parseExtras(from extrasData: [String: Any]?) -> CricketInningsBreakdown.ExtrasBreakdown {
        guard let extrasData else {
            return .init(byes: 0, legByes: 0, wides: 0, noBalls: 0, total: 0)
        }

        let byes = (extrasData["byes"] as? NSNumber)?.intValue ?? 0
        let legByes = (extrasData["legByes"] as? NSNumber)?.intValue ?? 0
        let wides = (extrasData["wides"] as? NSNumber)?.intValue ?? 0
        let noBalls = (extrasData["noBalls"] as? NSNumber)?.intValue ?? 0
        let total = (extrasData["total"] as? NSNumber)?.intValue ?? (byes + legByes + wides + noBalls)

        return .init(byes: byes, legByes: legByes, wides: wides, noBalls: noBalls, total: total)
    }

    private static func parsePartnerships(from partnershipsData: [String: Any]?) -> [CricketInningsBreakdown.PartnershipLine] {
        guard let partnershipsData else { return [] }

        let pairs: [CricketInningsBreakdown.PartnershipLine] = partnershipsData.compactMap { key, value in
            guard let p = value as? [String: Any] else { return nil }
            let b1 = (p["bat1Name"] as? String) ?? "B1"
            let b2 = (p["bat2Name"] as? String) ?? "B2"
            let runs = (p["totalRuns"] as? NSNumber)?.intValue ?? 0
            let balls = (p["totalBalls"] as? NSNumber)?.intValue ?? 0
            return .init(id: key, batter1: b1, batter2: b2, runs: runs, balls: balls)
        }

        return pairs.sorted { lhs, rhs in
            if lhs.runs != rhs.runs { return lhs.runs > rhs.runs }
            return lhs.balls < rhs.balls
        }
    }

    private static func parseYetToBat(from batTeamDetails: [String: Any]) -> [String] {
        guard let batsmenData = batTeamDetails["batsmenData"] as? [String: Any] else {
            return []
        }

        let list: [(order: Int, name: String)] = batsmenData.compactMap { key, value in
            guard let batter = value as? [String: Any] else { return nil }
            let runs = (batter["runs"] as? NSNumber)?.intValue ?? 0
            let balls = (batter["balls"] as? NSNumber)?.intValue ?? 0
            let out = (batter["outDesc"] as? String) ?? ""
            guard runs == 0, balls == 0, out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            let name = (batter["batShortName"] as? String) ?? (batter["batName"] as? String) ?? key
            let order = Int(key.filter(\.isNumber)) ?? 999
            return (order, name)
        }

        return list.sorted(by: { $0.order < $1.order }).map(\.name)
    }

    private static func parseFallOfWickets(from wicketsData: [String: Any]?) -> [String] {
        guard let wicketsData else { return [] }

        let lines: [(number: Int, line: String)] = wicketsData.compactMap { _, value in
            guard let wicket = value as? [String: Any] else { return nil }
            let number = (wicket["wktNbr"] as? NSNumber)?.intValue ?? 0
            let runs = (wicket["wktRuns"] as? NSNumber)?.intValue ?? 0
            let over = (wicket["wktOver"] as? NSNumber)?.doubleValue ?? 0
            let batter = (wicket["batName"] as? String) ?? "Batter"
            return (number, "\(number)-\(runs) (\(batter), \(formatOvers(over)) ov)")
        }

        return lines
            .sorted { $0.number < $1.number }
            .map(\.line)
    }

    private static func extractJSONObject(afterToken token: String, in html: String) -> [String: Any]? {
        guard let tokenRange = html.range(of: token) else {
            return nil
        }

        guard let objectStart = html[tokenRange.upperBound...].firstIndex(of: "{"),
              let objectEnd = balancedObjectEnd(in: html, from: objectStart)
        else {
            return nil
        }

        let objectString = String(html[objectStart...objectEnd])

        if let data = objectString.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return object
        }

        if token.contains(#"\""#), let decoded = decodeEscapedJSONObject(objectString) {
            return decoded
        }

        return nil
    }

    private static func extractJSONArray(afterToken token: String, in html: String) -> Any? {
        guard let tokenRange = html.range(of: token) else {
            return nil
        }

        guard let arrayStart = html[tokenRange.upperBound...].firstIndex(of: "["),
              let arrayEnd = balancedArrayEnd(in: html, from: arrayStart)
        else {
            return nil
        }

        var arrayString = String(html[arrayStart...arrayEnd])
        if token.contains(#"\""#) {
            arrayString = arrayString
                .replacingOccurrences(of: #"\""#, with: #"""#)
                .replacingOccurrences(of: #"\/"#, with: #"/"#)
        }

        guard let data = arrayString.data(using: .utf8) else {
            return nil
        }
        return try? JSONSerialization.jsonObject(with: data)
    }

    private static func extractAllJSONArrays(afterToken token: String, in html: String) -> [Any] {
        var result: [Any] = []
        var searchStart = html.startIndex

        while let tokenRange = html.range(of: token, range: searchStart..<html.endIndex) {
            guard let arrayStart = html[tokenRange.upperBound...].firstIndex(of: "["),
                  let arrayEnd = balancedArrayEnd(in: html, from: arrayStart)
            else {
                searchStart = tokenRange.upperBound
                continue
            }

            var arrayString = String(html[arrayStart...arrayEnd])
            if token.contains(#"\""#) {
                arrayString = arrayString
                    .replacingOccurrences(of: #"\""#, with: #"""#)
                    .replacingOccurrences(of: #"\/"#, with: #"/"#)
            }

            if let data = arrayString.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) {
                result.append(object)
            }

            searchStart = html.index(after: arrayStart)
        }

        return result
    }

    private static func extractLoosePointsTableArrays(from html: String) -> [Any] {
        var result: [Any] = []
        var searchStart = html.startIndex

        while let pointsRange = html.range(of: "pointsTable", range: searchStart..<html.endIndex) {
            let afterToken = pointsRange.upperBound
            guard let colon = html[afterToken...].firstIndex(of: ":") else {
                searchStart = afterToken
                continue
            }
            guard let arrayStart = html[colon...].firstIndex(of: "["),
                  html.distance(from: colon, to: arrayStart) <= 8,
                  let arrayEnd = balancedArrayEnd(in: html, from: arrayStart)
            else {
                searchStart = afterToken
                continue
            }

            var arrayString = String(html[arrayStart...arrayEnd])
            arrayString = arrayString
                .replacingOccurrences(of: #"\""#, with: #"""#)
                .replacingOccurrences(of: #"\/"#, with: #"/"#)

            if let data = arrayString.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) {
                result.append(object)
            }

            searchStart = html.index(after: pointsRange.lowerBound)
        }

        return result
    }

    private static func parseLooseStandingRows(from html: String) -> [CricketStandingRow]? {
        let teamPattern = #""teamFullName":"([^"]+)"|"teamName":"([^"]+)""#
        guard let teamRegex = try? NSRegularExpression(pattern: teamPattern) else {
            return nil
        }

        let nsRange = NSRange(html.startIndex..., in: html)
        let matches = teamRegex.matches(in: html, range: nsRange)
        guard !matches.isEmpty else { return nil }

        var rows: [CricketStandingRow] = []
        var seenTeams = Set<String>()

        for match in matches {
            guard let fullRange = Range(match.range, in: html) else { continue }
            let team = (Range(match.range(at: 1), in: html).map { String(html[$0]) }
                ?? Range(match.range(at: 2), in: html).map { String(html[$0]) }
                ?? "Team")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !team.isEmpty else { continue }
            if seenTeams.contains(team) { continue }

            let suffix = String(html[fullRange.upperBound...].prefix(900))
            guard let played = extractInt(after: "\"matchesPlayed\":", in: suffix),
                  let won = extractInt(after: "\"matchesWon\":", in: suffix),
                  let lost = extractInt(after: "\"matchesLost\":", in: suffix),
                  let points = extractInt(after: "\"points\":", in: suffix)
            else {
                continue
            }

            let nrr = extractString(after: #""nrr":"#, in: suffix) ?? "-"
            seenTeams.insert(team)
            rows.append(
                CricketStandingRow(
                    id: "fallback-\(team)-\(rows.count)",
                    rank: rows.count + 1,
                    teamName: team,
                    teamShort: nil,
                    teamLogoURL: nil,
                    played: played,
                    won: won,
                    lost: lost,
                    points: points,
                    nrr: nrr
                )
            )
        }

        return rows.sorted {
            if $0.points != $1.points { return $0.points > $1.points }
            return $0.rank < $1.rank
        }.enumerated().map { index, row in
            CricketStandingRow(
                id: row.id,
                rank: index + 1,
                teamName: row.teamName,
                teamShort: row.teamShort,
                teamLogoURL: row.teamLogoURL,
                played: row.played,
                won: row.won,
                lost: row.lost,
                points: row.points,
                nrr: row.nrr
            )
        }
    }

    private static func extractInt(after token: String, in text: String) -> Int? {
        guard let range = text.range(of: token) else { return nil }
        let tail = text[range.upperBound...]
        let digits = tail.prefix { $0.isNumber || $0 == "-" }
        return Int(digits)
    }

    private static func extractString(after token: String, in text: String) -> String? {
        guard let range = text.range(of: token) else { return nil }
        let tail = text[range.upperBound...]
        guard let end = tail.firstIndex(of: "\"") else { return nil }
        let value = String(tail[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func extractPointsTableURL(from html: String) -> URL? {
        let escapedPattern = #"\\"href\\":\\"([^\\"]+/points-table)\\"\\,\\"tabTitle\\":\\"Points Table\\""#
        let plainPattern = #""href":"([^"]+/points-table)","tabTitle":"Points Table""#

        let candidates = [escapedPattern, plainPattern]
        for pattern in candidates {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let nsRange = NSRange(html.startIndex..., in: html)
            guard let match = regex.firstMatch(in: html, range: nsRange),
                  match.numberOfRanges > 1,
                  let hrefRange = Range(match.range(at: 1), in: html)
            else { continue }

            let href = String(html[hrefRange])
                .replacingOccurrences(of: #"\/"#, with: "/")
            if let url = URL(string: href, relativeTo: baseURL)?.absoluteURL {
                return url
            }
        }

        return nil
    }

    private static func extractSeriesPointsTableURL(from html: String) -> URL? {
        let patterns = [
            #"/cricket-series/(\d+)/([^/"]+)/points-table"#,
            #"/cricket-series/(\d+)/([^/"]+)/matches"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let nsRange = NSRange(html.startIndex..., in: html)
            guard let match = regex.firstMatch(in: html, range: nsRange),
                  match.numberOfRanges > 2,
                  let idRange = Range(match.range(at: 1), in: html),
                  let slugRange = Range(match.range(at: 2), in: html)
            else { continue }

            let seriesID = String(html[idRange])
            let slug = String(html[slugRange])
            let href = "/cricket-series/\(seriesID)/\(slug)/points-table"
            if let url = URL(string: href, relativeTo: baseURL)?.absoluteURL {
                return url
            }
        }

        return nil
    }

    private static func extractVenue(from html: String) -> String? {
        let pattern = #""location":\{"@type":"Place","name":"([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: html)
        else {
            return nil
        }
        let venue = String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        return venue.isEmpty ? nil : venue
    }

    private static func extractLooseFact(label: String, from html: String) -> String? {
        let plain = html
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\/", with: "/")

        let pattern = "\(NSRegularExpression.escapedPattern(for: label))\\s*:?\\s*([^\\n\\r|<]{4,220})"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: plain, range: NSRange(plain.startIndex..., in: plain)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: plain)
        else {
            return nil
        }

        let value = String(plain[range])
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return sanitizeLooseFact(value)
    }

    private static func extractPlayerOfMatch(from html: String) -> String? {
        let keyPatterns = [
            #""playerOfTheMatch"\s*:\s*"([^"]{2,120})""#,
            #""manOfTheMatch"\s*:\s*"([^"]{2,120})""#,
            #"\"playerOfTheMatch\"\s*:\s*\"([^\"]{2,120})\""#,
            #"\"manOfTheMatch\"\s*:\s*\"([^\"]{2,120})\""#,
        ]

        for pattern in keyPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: html)
            else { continue }

            let value = html[range]
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\/", with: "/")
            if let cleaned = sanitizeLooseFact(String(value)) {
                return cleaned
            }
        }

        let labelCandidates = [
            "Player of the Match",
            "Man of the Match",
            "POTM"
        ]
        for label in labelCandidates {
            if let value = extractLooseFact(label: label, from: html) {
                return value
            }
        }
        return nil
    }

    private static func sanitizeLooseFact(_ raw: String) -> String? {
        let clean = raw
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ":,-•|"))
        guard !clean.isEmpty else { return nil }
        guard clean.count <= 160 else { return nil }
        return clean
    }

    private static func extractEscapedMatchObjects(from html: String) -> [String] {
        let token = #"\"matchInfo\":{\"matchId\":"#
        var objects: [String] = []
        var searchStart = html.startIndex

        while let tokenRange = html.range(of: token, range: searchStart..<html.endIndex) {
            guard let start = html[..<tokenRange.lowerBound].lastIndex(of: "{"),
                  let end = balancedObjectEnd(in: html, from: start)
            else {
                searchStart = tokenRange.upperBound
                continue
            }

            objects.append(String(html[start...end]))
            searchStart = html.index(after: end)
        }

        return objects
    }

    private static func balancedObjectEnd(in text: String, from start: String.Index) -> String.Index? {
        var depth = 0
        var index = start

        while index < text.endIndex {
            let char = text[index]

            if char == "{" { depth += 1 }
            if char == "}" {
                depth -= 1
                if depth == 0 {
                    return index
                }
            }

            index = text.index(after: index)
        }

        return nil
    }

    private static func balancedArrayEnd(in text: String, from start: String.Index) -> String.Index? {
        var depth = 0
        var index = start

        while index < text.endIndex {
            let char = text[index]

            if char == "[" { depth += 1 }
            if char == "]" {
                depth -= 1
                if depth == 0 {
                    return index
                }
            }

            index = text.index(after: index)
        }

        return nil
    }

    private static func decodeEscapedJSONObject(_ raw: String) -> [String: Any]? {
        let jsonString = raw
            .replacingOccurrences(of: #"\""#, with: #"""#)
            .replacingOccurrences(of: #"\/"#, with: #"/"#)

        guard let data = jsonString.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        return object
    }

    private static func formatTeamScore(_ scoreObject: [String: Any]?) -> (summary: String, innings: [String], details: [CricketInning]) {
        guard let scoreObject else { return ("", [], []) }

        let inningsKeys = scoreObject.keys.sorted()
        var inningsParts: [String] = []
        var inningsDetails: [CricketInning] = []

        for key in inningsKeys {
            guard let innings = scoreObject[key] as? [String: Any] else { continue }

            let runs = (innings["runs"] as? NSNumber)?.intValue
            let wickets = (innings["wickets"] as? NSNumber)?.intValue
            let overs = (innings["overs"] as? NSNumber)?.doubleValue

            guard let runs else { continue }

            var text = "\(runs)"
            if let wickets {
                text += "/\(wickets)"
            }
            if let overs {
                text += " (\(formatOvers(overs)))"
            }

            inningsParts.append(text)

            let inningNumber = Int(key.filter(\.isNumber)) ?? (inningsDetails.count + 1)
            inningsDetails.append(
                CricketInning(
                    number: inningNumber,
                    runs: runs,
                    wickets: wickets,
                    overs: overs
                )
            )
        }

        inningsDetails.sort { $0.number < $1.number }
        return (inningsParts.joined(separator: " & "), inningsParts, inningsDetails)
    }

    private static func formatOvers(_ value: Double) -> String {
        if value.rounded(.towardZero) == value {
            return "\(Int(value))"
        }
        return String(format: "%.1f", value)
    }
}
