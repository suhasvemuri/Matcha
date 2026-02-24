import Foundation

actor IPTVResolver {
    static let shared = IPTVResolver()

    struct MatchQuery {
        let sport: String
        let league: String
        let homeTeam: String
        let awayTeam: String
        let startDate: Date
        let isLive: Bool
        let isUpcoming: Bool
        let broadcastHints: [String]
    }

    struct MatchResolution {
        let streamURL: URL
        let channelName: String
        let programTitle: String?
        let confidence: Double
        let matchedBy: String
        let requestHeaders: [String: String]
    }

    private struct IPTVChannel {
        let names: [String]
        let normalizedNames: Set<String>
        let tvgID: String?
        let normalizedTvgID: String?
        let groupTitle: String?
        let streamURL: URL
        let requestHeaders: [String: String]
    }

    private struct EPGProgram {
        let channelID: String?
        let normalizedChannelID: String?
        let channelNames: [String]
        let normalizedChannelNames: [String]
        let title: String
        let description: String?
        let start: Date
        let end: Date
    }

    private var cachedSourceURL = ""
    private var lastLoadedAt = Date.distantPast
    private var channelsByNormalizedName: [String: IPTVChannel] = [:]
    private var channels: [IPTVChannel] = []

    private var cachedEPGURL = ""
    private var lastEPGLoadedAt = Date.distantPast
    private var cachedPrograms: [EPGProgram] = []
    private var epgChannelNamesByID: [String: [String]] = [:]

    func resolveStreamURL(channelNames: [String], m3uURLString: String) async -> URL? {
        await resolveStream(channelNames: channelNames, m3uURLString: m3uURLString)?.streamURL
    }

    func resolveStream(channelNames: [String], m3uURLString: String) async -> MatchResolution? {
        guard let sourceURL = URL(string: m3uURLString), !channelNames.isEmpty else {
            return nil
        }

        let shouldReload = sourceURL.absoluteString != cachedSourceURL
            || Date().timeIntervalSince(lastLoadedAt) > 900

        if shouldReload {
            await reloadChannels(from: sourceURL)
        }

        for channel in channelNames {
            let normalized = Self.normalize(channel)
            for candidate in Self.aliasCandidates(for: normalized) {
                if let exact = channelsByNormalizedName[candidate] {
                    return MatchResolution(
                        streamURL: exact.streamURL,
                        channelName: channel,
                        programTitle: nil,
                        confidence: 0.90,
                        matchedBy: "channel_name",
                        requestHeaders: exact.requestHeaders
                    )
                }
            }
        }

        for channel in channelNames {
            let normalized = Self.normalize(channel)
            for candidate in Self.aliasCandidates(for: normalized) {
                if let fuzzy = channelsByNormalizedName.first(where: { key, _ in
                    key.contains(candidate) || candidate.contains(key)
                })?.value {
                    return MatchResolution(
                        streamURL: fuzzy.streamURL,
                        channelName: channel,
                        programTitle: nil,
                        confidence: 0.75,
                        matchedBy: "channel_name_fuzzy",
                        requestHeaders: fuzzy.requestHeaders
                    )
                }
            }
        }

        return nil
    }

    func resolveMatchStream(
        query: MatchQuery,
        m3uURLString: String,
        epgURLString: String?
    ) async -> MatchResolution? {
        let all = await resolveMatchStreams(
            query: query,
            m3uURLString: m3uURLString,
            epgURLString: epgURLString,
            limit: 6
        )
        return all.first
    }

    func resolveMatchStreams(
        query: MatchQuery,
        m3uURLString: String,
        epgURLString: String?,
        limit: Int = 6
    ) async -> [MatchResolution] {
        guard (query.isLive || query.isUpcoming),
              let sourceURL = URL(string: m3uURLString)
        else { return [] }

        let shouldReloadM3U = sourceURL.absoluteString != cachedSourceURL
            || Date().timeIntervalSince(lastLoadedAt) > 900
        if shouldReloadM3U {
            await reloadChannels(from: sourceURL)
        }
        guard !channels.isEmpty else { return [] }

        var ranked: [MatchResolution] = []
        ranked.append(contentsOf: directMatches(query: query, limit: limit))

        if ranked.count >= limit {
            return deduplicateResolutions(ranked, limit: limit)
        }

        guard let epgURLString,
              let epgURL = URL(string: epgURLString),
              !epgURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return deduplicateResolutions(ranked, limit: limit)
        }

        let shouldReloadEPG = epgURL.absoluteString != cachedEPGURL
            || Date().timeIntervalSince(lastEPGLoadedAt) > 600
        if shouldReloadEPG {
            await reloadEPG(from: epgURL)
        }
        guard !cachedPrograms.isEmpty else {
            return deduplicateResolutions(ranked, limit: limit)
        }

        ranked.append(contentsOf: bestEPGMatches(query: query, limit: max(1, limit)))
        return deduplicateResolutions(ranked, limit: limit)
    }

    private func reloadChannels(from sourceURL: URL) async {
        do {
            let (data, _) = try await URLSession.shared.data(from: sourceURL)
            guard let text = String(data: data, encoding: .utf8) else { return }

            let parsed = Self.parseM3UChannels(text)
            channels = parsed
            channelsByNormalizedName = Self.channelMap(from: parsed)
            cachedSourceURL = sourceURL.absoluteString
            lastLoadedAt = Date()
        } catch {
            print("Failed to fetch IPTV playlist:", error)
        }
    }

    static func parseM3U(_ content: String) -> [String: URL] {
        var map: [String: URL] = [:]
        for (key, channel) in channelMap(from: parseM3UChannels(content)) {
            map[key] = channel.streamURL
        }
        return map
    }

    private static func parseM3UChannels(_ content: String) -> [IPTVChannel] {
        var result: [IPTVChannel] = []
        let lines = content.components(separatedBy: .newlines)

        var pendingNames: [String] = []
        var pendingTvgID: String?
        var pendingGroupTitle: String?
        var pendingHeaders: [String: String] = [:]

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("#EXTINF") {
                pendingNames = extractNames(from: line)
                pendingTvgID = captureQuotedAttribute("tvg-id", from: line)
                pendingGroupTitle = captureQuotedAttribute("group-title", from: line)
                pendingHeaders = [:]
                continue
            }

            if line.lowercased().hasPrefix("#extvlcopt:") {
                let payload = String(line.dropFirst("#EXTVLCOPT:".count))
                let parts = payload.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                if parts.count == 2,
                   let canonicalKey = canonicalHeaderName(for: String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)) {
                    let headerValue = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !headerValue.isEmpty {
                        pendingHeaders[canonicalKey] = headerValue
                    }
                }
                continue
            }

            if line.hasPrefix("#") { continue }

            let parsedStream = parseStreamURLAndHeaders(from: line)
            guard let streamURL = parsedStream.url else {
                pendingNames = []
                pendingTvgID = nil
                pendingGroupTitle = nil
                pendingHeaders = [:]
                continue
            }

            let names = pendingNames.isEmpty ? [line] : pendingNames
            let normalized = Set(names.map(normalize).filter { !$0.isEmpty })
            if !normalized.isEmpty {
                let mergedHeaders = pendingHeaders.merging(parsedStream.headers) { _, latest in latest }
                result.append(
                    IPTVChannel(
                        names: names,
                        normalizedNames: normalized,
                        tvgID: pendingTvgID,
                        normalizedTvgID: pendingTvgID.map(normalize),
                        groupTitle: pendingGroupTitle,
                        streamURL: streamURL,
                        requestHeaders: mergedHeaders
                    )
                )
            }

            pendingNames = []
            pendingTvgID = nil
            pendingGroupTitle = nil
            pendingHeaders = [:]
        }

        return result
    }

    private static func channelMap(from channels: [IPTVChannel]) -> [String: IPTVChannel] {
        var result: [String: IPTVChannel] = [:]
        for channel in channels {
            for normalized in channel.normalizedNames {
                result[normalized] = channel
            }
            if let id = channel.normalizedTvgID, !id.isEmpty {
                result[id] = channel
            }
        }
        return result
    }

    static func extractNames(from extinfLine: String) -> [String] {
        var names: [String] = []

        if let tvgName = captureQuotedAttribute("tvg-name", from: extinfLine) {
            names.append(tvgName)
        }

        if let channelID = captureQuotedAttribute("tvg-id", from: extinfLine) {
            names.append(channelID)
        }

        if let commaIndex = extinfLine.firstIndex(of: ",") {
            let displayName = String(extinfLine[extinfLine.index(after: commaIndex)...]).trimmingCharacters(in: .whitespaces)
            if !displayName.isEmpty {
                names.append(displayName)
            }
        }

        return Array(Set(names))
    }

    static func captureQuotedAttribute(_ key: String, from line: String) -> String? {
        let pattern = key + "=\"([^\"]+)\""
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        let range = NSRange(line.startIndex..., in: line)
        guard let match = regex.firstMatch(in: line, range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: line)
        else {
            return nil
        }

        return String(line[valueRange])
    }

    private static func parseStreamURLAndHeaders(from line: String) -> (url: URL?, headers: [String: String]) {
        let pieces = line.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        let rawURL = String(pieces[0]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: rawURL) else { return (nil, [:]) }

        guard pieces.count > 1 else { return (url, [:]) }

        var headers: [String: String] = [:]
        let rawOptions = String(pieces[1])
        for pair in rawOptions.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let rawKey = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            let key = canonicalHeaderName(for: rawKey) ?? rawKey
            let rawValue = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            let decodedValue = rawValue.removingPercentEncoding ?? rawValue
            if !key.isEmpty, !decodedValue.isEmpty {
                headers[key] = decodedValue
            }
        }
        return (url, headers)
    }

    private static func canonicalHeaderName(for raw: String) -> String? {
        let key = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        switch key {
        case "user-agent", "http-user-agent", "ua":
            return "User-Agent"
        case "referer", "referrer", "http-referrer", "http-referer":
            return "Referer"
        case "origin":
            return "Origin"
        case "cookie":
            return "Cookie"
        case "authorization":
            return "Authorization"
        default:
            return nil
        }
    }

    static func normalize(_ input: String) -> String {
        let lower = input.lowercased()
        let cleanedScalars = lower.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) { return Character(scalar) }
            return " "
        }
        let cleaned = String(cleanedScalars)
        return cleaned
            .split(separator: " ")
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func aliasCandidates(for normalized: String) -> [String] {
        guard !normalized.isEmpty else { return [] }

        var candidates = Set<String>()
        candidates.insert(normalized)

        let stripped = normalized
            .replacingOccurrences(of: " usa", with: "")
            .replacingOccurrences(of: " us", with: "")
            .replacingOccurrences(of: " hd", with: "")
            .replacingOccurrences(of: " 4k", with: "")
            .replacingOccurrences(of: " fhd", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !stripped.isEmpty { candidates.insert(stripped) }

        let aliases: [String: [String]] = [
            "nbc sports": ["nbcsn"],
            "tnt sports": ["tnt"],
            "fox sports 1": ["fs1"],
            "fox sports 2": ["fs2"],
            "espn deportes": ["espn dep"],
            "bein sports": ["bein", "be in sports"],
            "sky sports": ["skysp", "sky"],
            "peacock": ["peacock tv"]
        ]

        for (key, values) in aliases {
            if stripped.contains(key) || key.contains(stripped) {
                values.forEach { candidates.insert($0) }
            }
        }

        return Array(candidates)
    }

    private func directMatches(query: MatchQuery, limit: Int) -> [MatchResolution] {
        let hints = query.broadcastHints
        guard !hints.isEmpty else { return [] }

        var results: [MatchResolution] = []
        for raw in hints where !Self.normalize(raw).isEmpty {
            if let channel = resolveFirstMatchChannel(for: [raw]) {
                results.append(
                    MatchResolution(
                        streamURL: channel.streamURL,
                        channelName: raw,
                        programTitle: nil,
                        confidence: 0.96,
                        matchedBy: "broadcast_hint",
                        requestHeaders: channel.requestHeaders
                    )
                )
                if results.count >= limit {
                    break
                }
            }
        }
        return deduplicateResolutions(results, limit: limit)
    }

    private func resolveFirstMatchChannel(for channelNames: [String]) -> IPTVChannel? {
        for channel in channelNames {
            let normalized = Self.normalize(channel)
            for candidate in Self.aliasCandidates(for: normalized) {
                if let exact = channelsByNormalizedName[candidate] {
                    return exact
                }
            }
        }

        for channel in channelNames {
            let normalized = Self.normalize(channel)
            for candidate in Self.aliasCandidates(for: normalized) {
                if let fuzzy = channelsByNormalizedName.first(where: { key, _ in
                    key.contains(candidate) || candidate.contains(key)
                })?.value {
                    return fuzzy
                }
            }
        }
        return nil
    }

    private func reloadEPG(from url: URL) async {
        do {
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
                return
            }
            guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
                return
            }

            let parsed = Self.parseXMLTV(text)
            cachedPrograms = parsed.programs
            epgChannelNamesByID = parsed.channelNamesByID
            cachedEPGURL = url.absoluteString
            lastEPGLoadedAt = Date()
        } catch {
            print("Failed to fetch IPTV EPG:", error)
        }
    }

    private func bestEPGMatches(query: MatchQuery, limit: Int) -> [MatchResolution] {
        let now = Date()
        let windowStart: Date
        let windowEnd: Date
        if query.isLive {
            windowStart = now.addingTimeInterval(-120 * 60)
            windowEnd = now.addingTimeInterval(45 * 60)
        } else {
            // EPG start times can drift due to timezone/feed offsets; keep upcoming window forgiving.
            windowStart = query.startDate.addingTimeInterval(-8 * 60 * 60)
            windowEnd = query.startDate.addingTimeInterval(14 * 60 * 60)
        }

        let qHome = Self.normalize(query.homeTeam)
        let qAway = Self.normalize(query.awayTeam)
        let qLeague = Self.normalize(query.league)
        let leagueTokens = Set(qLeague.split(separator: " ").map(String.init).filter { $0.count > 2 })
        let homeTokens = Set(qHome.split(separator: " ").map(String.init).filter { $0.count > 2 })
        let awayTokens = Set(qAway.split(separator: " ").map(String.init).filter { $0.count > 2 })

        var ranked: [(program: EPGProgram, channel: IPTVChannel, score: Double)] = []

        for program in cachedPrograms {
            guard program.end >= windowStart, program.start <= windowEnd else { continue }

            guard let channel = channelForProgram(program) else { continue }
            guard isLikelySportsChannel(channel, program: program) else { continue }

            let title = Self.normalize(program.title)
            let desc = Self.normalize(program.description ?? "")

            var score = 0.0
            let titleTokens = Set(title.split(separator: " ").map(String.init))
            let descTokens = Set(desc.split(separator: " ").map(String.init))

            let homeHits = Double(titleTokens.intersection(homeTokens).count) + 0.5 * Double(descTokens.intersection(homeTokens).count)
            let awayHits = Double(titleTokens.intersection(awayTokens).count) + 0.5 * Double(descTokens.intersection(awayTokens).count)
            let leagueHits = Double(titleTokens.intersection(leagueTokens).count) + 0.4 * Double(descTokens.intersection(leagueTokens).count)

            if homeHits > 0 { score += min(3.0, homeHits) }
            if awayHits > 0 { score += min(3.0, awayHits) }
            if homeHits > 0 && awayHits > 0 { score += 2.0 }
            if leagueHits > 0 { score += min(2.5, leagueHits) }
            if qLeague.contains("world cup") && (titleTokens.contains("wc") || descTokens.contains("wc")) {
                score += 1.2
            }
            if query.sport == "cricket" && (title.contains("cricket") || desc.contains("cricket")) {
                score += 0.9
            }
            if query.sport == "soccer" && (title.contains("soccer") || title.contains("football") || desc.contains("soccer") || desc.contains("football")) {
                score += 0.8
            }

            if query.broadcastHints.contains(where: { hint in
                let n = Self.normalize(hint)
                return channel.normalizedNames.contains(where: { $0.contains(n) || n.contains($0) })
            }) {
                score += 2.5
            }

            let timeDelta = abs(program.start.timeIntervalSince(query.startDate))
            if timeDelta <= 30 * 60 { score += 1.5 }
            else if timeDelta <= 90 * 60 { score += 0.8 }

            if score < 1.8 { continue }

            ranked.append((program, channel, score))
        }

        let sorted = ranked.sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.program.start < rhs.program.start
            }
            return lhs.score > rhs.score
        }

        var results: [MatchResolution] = []
        for best in sorted {
            let primaryName = best.channel.names.first ?? best.program.channelNames.first ?? "Sports Channel"
            results.append(
                MatchResolution(
                    streamURL: best.channel.streamURL,
                    channelName: primaryName,
                    programTitle: best.program.title,
                    confidence: min(0.99, 0.35 + best.score / 12.0),
                    matchedBy: "epg",
                    requestHeaders: best.channel.requestHeaders
                )
            )
            if results.count >= limit { break }
        }

        return deduplicateResolutions(results, limit: limit)
    }

    private func deduplicateResolutions(_ resolutions: [MatchResolution], limit: Int) -> [MatchResolution] {
        var seen: Set<String> = []
        var out: [MatchResolution] = []
        for candidate in resolutions {
            let key = "\(candidate.streamURL.absoluteString)|\(Self.normalize(candidate.channelName))"
            if seen.contains(key) { continue }
            seen.insert(key)
            out.append(candidate)
            if out.count >= limit { break }
        }
        return out
    }

    private func channelForProgram(_ program: EPGProgram) -> IPTVChannel? {
        if let id = program.normalizedChannelID {
            if let byID = channels.first(where: { $0.normalizedTvgID == id }) {
                return byID
            }
        }

        for name in program.normalizedChannelNames {
            if let exact = channels.first(where: { $0.normalizedNames.contains(name) }) {
                return exact
            }
            if let fuzzy = channels.first(where: { channel in
                channel.normalizedNames.contains(where: { $0.contains(name) || name.contains($0) })
            }) {
                return fuzzy
            }
        }
        return nil
    }

    private func isLikelySportsChannel(_ channel: IPTVChannel, program: EPGProgram) -> Bool {
        let hayParts = [
            channel.names.joined(separator: " "),
            channel.groupTitle ?? "",
            program.title,
            program.description ?? ""
        ]
        let hay = hayParts.joined(separator: " ").lowercased()

        let sportsTerms = [
            "sport", "espn", "star sports", "sky sports", "tnt", "fox sports", "bein", "sonysports",
            "sony sports", "supersport", "willow", "astro", "ten sports", "premier sports"
        ]
        return sportsTerms.contains(where: { hay.contains($0) })
    }

    private static func parseXMLTV(_ text: String) -> (programs: [EPGProgram], channelNamesByID: [String: [String]]) {
        let channelPattern = #"<channel[^>]*id="([^"]+)"[^>]*>(.*?)</channel>"#
        let displayPattern = #"<display-name[^>]*>(.*?)</display-name>"#
        let programPattern = #"<programme\s+([^>]+)>(.*?)</programme>"#

        var channelNamesByID: [String: [String]] = [:]

        if let channelRegex = try? NSRegularExpression(pattern: channelPattern, options: [.dotMatchesLineSeparators, .caseInsensitive]),
           let displayRegex = try? NSRegularExpression(pattern: displayPattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) {
            let nsRange = NSRange(text.startIndex..., in: text)
            channelRegex.matches(in: text, range: nsRange).forEach { match in
                guard match.numberOfRanges > 2,
                      let idRange = Range(match.range(at: 1), in: text),
                      let bodyRange = Range(match.range(at: 2), in: text)
                else { return }
                let id = Self.normalize(String(text[idRange]))
                let body = String(text[bodyRange])
                let names = displayRegex.matches(in: body, range: NSRange(body.startIndex..., in: body)).compactMap { m -> String? in
                    guard m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: body) else { return nil }
                    let cleaned = Self.normalize(Self.stripHTML(String(body[r])))
                    return cleaned.isEmpty ? nil : cleaned
                }
                channelNamesByID[id] = Array(Set(names))
            }
        }

        var programs: [EPGProgram] = []

        if let progRegex = try? NSRegularExpression(pattern: programPattern, options: [.dotMatchesLineSeparators, .caseInsensitive]),
           let titleRegex = try? NSRegularExpression(pattern: #"<title[^>]*>(.*?)</title>"#, options: [.dotMatchesLineSeparators, .caseInsensitive]),
           let descRegex = try? NSRegularExpression(pattern: #"<desc[^>]*>(.*?)</desc>"#, options: [.dotMatchesLineSeparators, .caseInsensitive]) {
            let nsRange = NSRange(text.startIndex..., in: text)
            progRegex.matches(in: text, range: nsRange).forEach { match in
                guard match.numberOfRanges > 2,
                      let attrsRange = Range(match.range(at: 1), in: text),
                      let bodyRange = Range(match.range(at: 2), in: text)
                else { return }

                let attrs = String(text[attrsRange])
                let body = String(text[bodyRange])

                guard let startRaw = attribute("start", in: attrs),
                      let stopRaw = attribute("stop", in: attrs),
                      let start = parseXMLTVDate(startRaw),
                      let end = parseXMLTVDate(stopRaw)
                else { return }

                let rawChannelID = attribute("channel", in: attrs)
                let channelID = rawChannelID.map(Self.normalize)
                let channelNames = channelID.flatMap { channelNamesByID[$0] } ?? []

                let title: String = {
                    let matches = titleRegex.matches(in: body, range: NSRange(body.startIndex..., in: body))
                    guard let first = matches.first, first.numberOfRanges > 1, let r = Range(first.range(at: 1), in: body) else {
                        return ""
                    }
                    return Self.stripHTML(String(body[r])).trimmingCharacters(in: .whitespacesAndNewlines)
                }()
                guard !title.isEmpty else { return }

                let desc: String? = {
                    let matches = descRegex.matches(in: body, range: NSRange(body.startIndex..., in: body))
                    guard let first = matches.first, first.numberOfRanges > 1, let r = Range(first.range(at: 1), in: body) else {
                        return nil
                    }
                    let cleaned = Self.stripHTML(String(body[r])).trimmingCharacters(in: .whitespacesAndNewlines)
                    return cleaned.isEmpty ? nil : cleaned
                }()

                programs.append(
                    EPGProgram(
                        channelID: rawChannelID,
                        normalizedChannelID: channelID,
                        channelNames: channelNames,
                        normalizedChannelNames: channelNames.map(Self.normalize),
                        title: title,
                        description: desc,
                        start: start,
                        end: end
                    )
                )
            }
        }

        return (programs, channelNamesByID)
    }

    private static func attribute(_ key: String, in attrs: String) -> String? {
        captureQuotedAttribute(key, from: attrs)
    }

    private static func parseXMLTVDate(_ raw: String) -> Date? {
        // Common XMLTV: "yyyyMMddHHmmss Z" or with compact offset
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized: String
        if cleaned.count >= 19, cleaned[cleaned.index(cleaned.startIndex, offsetBy: 14)] == " " {
            normalized = cleaned
        } else if cleaned.count >= 18 {
            let prefix = cleaned.prefix(14)
            let suffix = cleaned.suffix(cleaned.count - 14)
            normalized = "\(prefix) \(suffix)"
        } else {
            normalized = cleaned
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMddHHmmss Z"
        if let date = formatter.date(from: normalized) {
            return date
        }

        let fallback = DateFormatter()
        fallback.locale = Locale(identifier: "en_US_POSIX")
        fallback.dateFormat = "yyyyMMddHHmmss"
        return fallback.date(from: String(cleaned.prefix(14)))
    }

    private static func stripHTML(_ input: String) -> String {
        input
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}
