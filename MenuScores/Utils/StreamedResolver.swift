import Foundation

enum StreamedResolver {
    private struct APIBadResponse: Error {}

    struct Config {
        let enabled: Bool
        let baseURLString: String

        var normalizedBaseURL: String {
            let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return "https://streamed.st"
            }
            return trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        }
    }

    private struct APIMatch: Decodable {
        struct Teams: Decodable {
            struct Side: Decodable {
                let name: String
            }
            let home: Side?
            let away: Side?
        }

        struct Source: Decodable {
            let source: String
            let id: String
            private enum CodingKeys: String, CodingKey { case source, id }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                source = (try? c.decode(String.self, forKey: .source)) ?? ""
                if let idString = try? c.decode(String.self, forKey: .id) {
                    id = idString
                } else if let idInt = try? c.decode(Int.self, forKey: .id) {
                    id = String(idInt)
                } else {
                    id = ""
                }
            }
        }

        let id: String
        let title: String
        let category: String
        let date: Int64
        let teams: Teams?
        let sources: [Source]
        private enum CodingKeys: String, CodingKey {
            case id, title, category, date, teams, sources
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            if let idString = try? c.decode(String.self, forKey: .id) {
                id = idString
            } else if let idInt = try? c.decode(Int.self, forKey: .id) {
                id = String(idInt)
            } else {
                id = ""
            }
            title = (try? c.decode(String.self, forKey: .title)) ?? ""
            category = (try? c.decode(String.self, forKey: .category)) ?? ""
            if let dateInt = try? c.decode(Int64.self, forKey: .date) {
                date = dateInt
            } else if let dateDouble = try? c.decode(Double.self, forKey: .date) {
                date = Int64(dateDouble)
            } else {
                date = 0
            }
            teams = try? c.decode(Teams.self, forKey: .teams)
            sources = (try? c.decode([Source].self, forKey: .sources)) ?? []
        }
    }

    private struct APIStream: Decodable {
        let id: String?
        let streamNo: Int?
        let language: String?
        let hd: Bool?
        let embedUrl: String?
        let streamUrl: String?
        let url: String?
        let source: String?

        var anyURLString: String? {
            embedUrl ?? streamUrl ?? url
        }
    }

    private struct APIStreamEnvelope: Decodable {
        let streams: [APIStream]
    }

    private struct RankedMatch {
        let item: APIMatch
        let score: Double
    }

    static func resolveMatchStreams(
        query: IPTVResolver.MatchQuery,
        config: Config,
        limit: Int = 4
    ) async -> [IPTVResolver.MatchResolution] {
        guard config.enabled else { return [] }

        let bases = candidateBases(from: config.normalizedBaseURL)
        let base = bases.first ?? config.normalizedBaseURL
        guard URL(string: base) != nil else { return [] }

        guard let matches = await fetchMatches(query: query, bases: bases), !matches.isEmpty else {
            return []
        }

        let ranked = rank(matches: matches, query: query).prefix(4)
        var results: [IPTVResolver.MatchResolution] = []

        let candidates = ranked.isEmpty ? matches.prefix(3).map { RankedMatch(item: $0, score: 2.3) } : Array(ranked)

        for candidate in candidates {
            for source in candidate.item.sources.prefix(4) {
                guard let streams = await fetchStreams(source: source, bases: bases), !streams.isEmpty else { continue }

                for stream in streams.prefix(3) {
                    guard let url = normalizedStreamURL(from: stream.anyURLString, baseURLString: base) else { continue }
                    let sourceName = stream.source ?? source.source
                    let label = streamLabel(sourceName: sourceName, stream: stream)
                    results.append(
                        IPTVResolver.MatchResolution(
                            streamURL: url,
                            channelName: label,
                            programTitle: candidate.item.title,
                            confidence: min(0.95, 0.45 + candidate.score / 10.0),
                            matchedBy: "streamed",
                            requestHeaders: [:]
                        )
                    )
                    if results.count >= limit {
                        return dedupe(results, limit: limit)
                    }
                }
            }
        }

        return dedupe(results, limit: limit)
    }

    private static func rank(matches: [APIMatch], query: IPTVResolver.MatchQuery) -> [RankedMatch] {
        let now = Date()
        let qSport = normalize(query.sport)
        let qLeague = normalize(query.league)
        let qHome = normalize(query.homeTeam)
        let qAway = normalize(query.awayTeam)
        let homeTokens = Set(qHome.split(separator: " ").map(String.init).filter { $0.count > 2 })
        let awayTokens = Set(qAway.split(separator: " ").map(String.init).filter { $0.count > 2 })
        let leagueTokens = Set(qLeague.split(separator: " ").map(String.init).filter { $0.count > 2 })

        return matches.compactMap { match in
            let matchDate = Date(timeIntervalSince1970: Double(match.date) / 1000.0)
            if !query.isLive && matchDate < now.addingTimeInterval(-2 * 60 * 60) { return nil }

            let title = normalize(match.title)
            let category = normalize(match.category)
            let homeName = normalize(match.teams?.home?.name ?? "")
            let awayName = normalize(match.teams?.away?.name ?? "")
            let titleTokens = Set(title.split(separator: " ").map(String.init))

            var score = 0.0

            if qSport == "soccer", category.contains("football") { score += 1.4 }
            if qSport == "cricket", category.contains("cricket") { score += 1.4 }
            if category.contains(qSport) { score += 1.2 }

            let homeHits = Double(titleTokens.intersection(homeTokens).count) + tokenContainmentScore(name: homeName, tokens: homeTokens)
            let awayHits = Double(titleTokens.intersection(awayTokens).count) + tokenContainmentScore(name: awayName, tokens: awayTokens)
            if homeHits > 0 { score += min(3.0, homeHits) }
            if awayHits > 0 { score += min(3.0, awayHits) }
            if homeHits > 0 && awayHits > 0 { score += 2.4 }

            let leagueHits = Double(titleTokens.intersection(leagueTokens).count)
            if leagueHits > 0 { score += min(1.6, leagueHits) }

            let timeDelta = abs(matchDate.timeIntervalSince(query.startDate))
            if timeDelta <= 45 * 60 { score += 1.5 }
            else if timeDelta <= 2.5 * 60 * 60 { score += 0.8 }

            if score < 1.35 { return nil }
            return RankedMatch(item: match, score: score)
        }
        .sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.item.date < rhs.item.date
            }
            return lhs.score > rhs.score
        }
    }

    private static func tokenContainmentScore(name: String, tokens: Set<String>) -> Double {
        guard !name.isEmpty, !tokens.isEmpty else { return 0 }
        return Double(tokens.filter { name.contains($0) }.count) * 0.9
    }

    private static func streamLabel(sourceName: String, stream: APIStream) -> String {
        var bits: [String] = ["Streamed \(sourceName.uppercased())"]
        if let no = stream.streamNo { bits.append("#\(no)") }
        if let lang = stream.language, !lang.isEmpty { bits.append(lang) }
        if stream.hd == true { bits.append("HD") }
        return bits.joined(separator: " • ")
    }

    private static func normalize(_ value: String) -> String {
        IPTVResolver.normalize(value)
    }

    private static func dedupe(_ values: [IPTVResolver.MatchResolution], limit: Int) -> [IPTVResolver.MatchResolution] {
        var seen: Set<String> = []
        var out: [IPTVResolver.MatchResolution] = []
        for value in values {
            let key = "\(value.streamURL.absoluteString)|\(normalize(value.channelName))"
            if seen.contains(key) { continue }
            seen.insert(key)
            out.append(value)
            if out.count >= limit { break }
        }
        return out
    }

    private static func candidateBases(from configured: String) -> [String] {
        let cleaned = configured.trimmingCharacters(in: .whitespacesAndNewlines)
        var bases: [String] = []
        if !cleaned.isEmpty { bases.append(cleaned) }
        if cleaned.contains("streamed.st") {
            bases.append(cleaned.replacingOccurrences(of: "streamed.st", with: "streamed.pk"))
        } else if cleaned.contains("streamed.pk") {
            bases.append(cleaned.replacingOccurrences(of: "streamed.pk", with: "streamed.st"))
        } else {
            bases.append("https://streamed.st")
            bases.append("https://streamed.pk")
        }
        return Array(NSOrderedSet(array: bases)) as? [String] ?? bases
    }

    private static func fetchMatches(query: IPTVResolver.MatchQuery, bases: [String]) async -> [APIMatch]? {
        let matchPaths = query.isLive
            ? ["/api/matches/live", "/api/matches/all-today", "/api/matches/all"]
            : ["/api/matches/all-today", "/api/matches/live", "/api/matches/all"]

        for base in bases {
            for path in matchPaths {
                guard let url = URL(string: "\(base)\(path)") else { continue }
                if let matches: [APIMatch] = try? await fetchJSON(url), !matches.isEmpty {
                    return matches
                }
            }
        }
        return nil
    }

    private static func fetchStreams(source: APIMatch.Source, bases: [String]) async -> [APIStream]? {
        let streamPaths = [
            "/api/stream/\(source.source)/\(source.id)",
            "/api/streams/\(source.source)/\(source.id)",
            "/api/source/\(source.source)/\(source.id)"
        ]
        for base in bases {
            for path in streamPaths {
                guard let url = URL(string: "\(base)\(path)") else { continue }
                if let arr: [APIStream] = try? await fetchJSON(url), !arr.isEmpty {
                    return arr
                }
                if let env: APIStreamEnvelope = try? await fetchJSON(url), !env.streams.isEmpty {
                    return env.streams
                }
            }
        }
        return nil
    }

    private static func normalizedStreamURL(from raw: String?, baseURLString: String) -> URL? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("//") {
            return URL(string: "https:\(trimmed)")
        }
        if let absolute = URL(string: trimmed), absolute.scheme?.hasPrefix("http") == true {
            return absolute
        }
        if let base = URL(string: baseURLString), let relative = URL(string: trimmed, relativeTo: base)?.absoluteURL {
            return relative
        }
        return nil
    }

    private static func fetchJSON<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue(url.deletingLastPathComponent().absoluteString, forHTTPHeaderField: "Referer")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw APIBadResponse()
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }
}
