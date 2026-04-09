import AppKit
import AVKit
import SwiftUI
import WebKit

private enum DashboardDateFormatters {
    static let isoWithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let iso: ISO8601DateFormatter = {
        ISO8601DateFormatter()
    }()

    static let cardDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = "EEE, MMM d • h:mm a"
        return formatter
    }()
}

private struct MenuWindowConfigurator: NSViewRepresentable {
    var onWindowAvailable: ((NSWindow) -> Void)? = nil

    final class Coordinator {
        weak var configuredWindow: NSWindow?
        var appearanceMode: String?
        var resizeObserver: NSObjectProtocol?
        var liveResizeEndObserver: NSObjectProtocol?

        deinit {
            if let resizeObserver {
                NotificationCenter.default.removeObserver(resizeObserver)
            }
            if let liveResizeEndObserver {
                NotificationCenter.default.removeObserver(liveResizeEndObserver)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configureWindowIfNeeded(view.window, coordinator: context.coordinator)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configureWindowIfNeeded(nsView.window, coordinator: context.coordinator)
        }
    }

    private func configureWindowIfNeeded(_ window: NSWindow?, coordinator: Coordinator) {
        guard let window else { return }
        let desiredMinSize = NSSize(width: 336, height: 420)
        let desiredMaxSize = NSSize(width: 520, height: 920)
        let appearanceMode = MatchaChromeStyle.mode(from: UserDefaults.standard.string(forKey: "matchaAppearanceMode"))
        let chromeBackground = MatchaChromeStyle.windowBackground(for: appearanceMode)

        let needsUpdate = coordinator.configuredWindow !== window
            || !window.styleMask.contains(.resizable)
            || window.minSize != desiredMinSize
            || window.maxSize != desiredMaxSize
            || coordinator.appearanceMode != appearanceMode.rawValue

        guard needsUpdate else { return }

        window.styleMask.insert(.resizable)
        window.minSize = desiredMinSize
        window.maxSize = desiredMaxSize
        window.isOpaque = false
        window.backgroundColor = chromeBackground
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.hasShadow = true
        window.isMovableByWindowBackground = false
        if let contentView = window.contentView {
            contentView.wantsLayer = true
            contentView.layerContentsRedrawPolicy = .duringViewResize
            contentView.layer?.masksToBounds = true
            contentView.layer?.cornerRadius = 18
            contentView.layer?.cornerCurve = .continuous
            contentView.layer?.backgroundColor = chromeBackground.cgColor
        }
        syncHostedContentLayout(in: window)
        installResizeObserversIfNeeded(for: window, coordinator: coordinator)
        coordinator.configuredWindow = window
        coordinator.appearanceMode = appearanceMode.rawValue
        onWindowAvailable?(window)
    }

    private func installResizeObserversIfNeeded(for window: NSWindow, coordinator: Coordinator) {
        guard coordinator.resizeObserver == nil, coordinator.liveResizeEndObserver == nil else { return }

        coordinator.resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: window,
            queue: .main
        ) { _ in
            syncHostedContentLayout(in: window)
        }

        coordinator.liveResizeEndObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didEndLiveResizeNotification,
            object: window,
            queue: .main
        ) { _ in
            syncHostedContentLayout(in: window)
        }
    }

    private func syncHostedContentLayout(in window: NSWindow) {
        guard let contentView = window.contentView else { return }
        let targetFrame = contentView.bounds
        let targetSize = targetFrame.size

        window.contentViewController?.preferredContentSize = targetSize

        if let controllerView = window.contentViewController?.view {
            controllerView.translatesAutoresizingMaskIntoConstraints = true
            controllerView.autoresizingMask = [.width, .height]
            if controllerView.frame != targetFrame {
                controllerView.frame = targetFrame
            }
            controllerView.invalidateIntrinsicContentSize()
            controllerView.needsLayout = true
            controllerView.layoutSubtreeIfNeeded()
        }

        for subview in contentView.subviews {
            subview.translatesAutoresizingMaskIntoConstraints = true
            subview.autoresizingMask = [.width, .height]
            if subview.frame != targetFrame {
                subview.frame = targetFrame
            }
            subview.invalidateIntrinsicContentSize()
            subview.needsLayout = true
            subview.layoutSubtreeIfNeeded()
        }

        contentView.needsLayout = true
        contentView.layoutSubtreeIfNeeded()
    }
}

private enum MatchaChromeStyle {
    static func mode(from rawValue: String?) -> MatchaAppearanceMode {
        MatchaAppearanceMode(rawValue: rawValue ?? "") ?? .darkFrosted
    }

    static func windowBackground(for mode: MatchaAppearanceMode) -> NSColor {
        switch mode {
        case .liquidGlass:
            return NSColor(calibratedRed: 0.29, green: 0.31, blue: 0.35, alpha: 0.18)
        case .frostedGlass:
            return NSColor(calibratedRed: 0.24, green: 0.26, blue: 0.30, alpha: 0.74)
        case .darkFrosted:
            return NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.12, alpha: 0.92)
        }
    }

    static func primaryForeground(for mode: MatchaAppearanceMode) -> Color {
        switch mode {
        case .liquidGlass:
            return Color.white.opacity(0.97)
        case .frostedGlass:
            return Color.white.opacity(0.95)
        case .darkFrosted:
            return Color.white.opacity(0.95)
        }
    }

    static func secondaryForeground(for mode: MatchaAppearanceMode) -> Color {
        switch mode {
        case .liquidGlass:
            return Color.white.opacity(0.82)
        case .frostedGlass:
            return Color.white.opacity(0.76)
        case .darkFrosted:
            return Color.white.opacity(0.72)
        }
    }

    static func tertiaryForeground(for mode: MatchaAppearanceMode) -> Color {
        switch mode {
        case .liquidGlass:
            return Color.white.opacity(0.64)
        case .frostedGlass:
            return Color.white.opacity(0.60)
        case .darkFrosted:
            return Color.white.opacity(0.54)
        }
    }
}

private struct MatchaChromePanelModifier: ViewModifier {
    let corner: CGFloat
    @AppStorage("matchaAppearanceMode") private var appearanceMode = MatchaAppearanceMode.darkFrosted.rawValue

    func body(content: Content) -> some View {
        let mode = MatchaChromeStyle.mode(from: appearanceMode)
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        content
            .background(chromeFill(for: mode, shape: shape))
            .overlay(
                shape.stroke(borderColor(for: mode), lineWidth: 0.7)
            )
            .shadow(color: shadowColor(for: mode), radius: shadowRadius(for: mode), y: 3)
    }

    @ViewBuilder
    private func chromeFill(for mode: MatchaAppearanceMode, shape: RoundedRectangle) -> some View {
        switch mode {
        case .liquidGlass:
            shape
                .fill(Color.white.opacity(0.008))
                .glassEffect(in: shape)
                .overlay(
                    shape.fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.055),
                                Color.white.opacity(0.015),
                                Color.black.opacity(0.01),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                )
                .overlay(alignment: .topLeading) {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.10),
                                    Color.white.opacity(0.03),
                                    Color.clear,
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 150, height: 12)
                        .offset(x: 18, y: 11)
                        .blur(radius: 10)
                        .blendMode(.screen)
                        .allowsHitTesting(false)
                }
        case .frostedGlass:
            shape
                .background(.regularMaterial, in: shape)
                .overlay(
                    shape.fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.06),
                                Color(red: 0.60, green: 0.64, blue: 0.70).opacity(0.03),
                                Color(red: 0.18, green: 0.20, blue: 0.24).opacity(0.14),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                )
                .overlay(
                    shape.fill(Color.white.opacity(0.012))
                )
        case .darkFrosted:
            shape
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.18, green: 0.20, blue: 0.25).opacity(0.92),
                            Color(red: 0.08, green: 0.10, blue: 0.14).opacity(0.96),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .background(.regularMaterial, in: shape)
                .overlay(
                    shape.fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.08),
                                Color.white.opacity(0.02),
                                Color.black.opacity(0.12),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                )
        }
    }

    private func borderColor(for mode: MatchaAppearanceMode) -> Color {
        switch mode {
        case .liquidGlass:
            return Color.white.opacity(0.14)
        case .frostedGlass:
            return Color.white.opacity(0.09)
        case .darkFrosted:
            return Color.white.opacity(0.08)
        }
    }

    private func shadowColor(for mode: MatchaAppearanceMode) -> Color {
        switch mode {
        case .liquidGlass:
            return .black.opacity(0.06)
        case .frostedGlass:
            return .black.opacity(0.08)
        case .darkFrosted:
            return .black.opacity(0.18)
        }
    }

    private func shadowRadius(for mode: MatchaAppearanceMode) -> CGFloat {
        switch mode {
        case .liquidGlass: return 7
        case .frostedGlass: return 9
        case .darkFrosted: return 10
        }
    }
}

private struct MatchaSectionCardModifier: ViewModifier {
    let corner: CGFloat
    let fillOpacity: CGFloat
    let strokeOpacity: CGFloat
    @AppStorage("matchaAppearanceMode") private var appearanceMode = MatchaAppearanceMode.darkFrosted.rawValue

    func body(content: Content) -> some View {
        let normalizedFill = max(0.0, min(fillOpacity, 1.0))
        let mode = MatchaChromeStyle.mode(from: appearanceMode)
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)

        return content
            .padding(8)
            .background(sectionBackground(for: mode, shape: shape, fill: normalizedFill))
            .overlay(
                shape.stroke(sectionStroke(for: mode, extra: strokeOpacity), lineWidth: 0.65)
            )
    }

    @ViewBuilder
    private func sectionBackground(for mode: MatchaAppearanceMode, shape: RoundedRectangle, fill: CGFloat) -> some View {
        switch mode {
        case .liquidGlass:
            shape
                .fill(Color.white.opacity(0.006))
                .glassEffect(in: shape)
                .overlay(
                    shape.fill(sectionGradient(for: mode, fill: fill))
                )
        case .frostedGlass, .darkFrosted:
            shape.fill(sectionGradient(for: mode, fill: fill))
        }
    }

    private func sectionGradient(for mode: MatchaAppearanceMode, fill: CGFloat) -> LinearGradient {
        switch mode {
        case .liquidGlass:
            return LinearGradient(
                colors: [
                    Color.white.opacity(0.05 + (0.015 * fill)),
                    Color.white.opacity(0.018 + (0.008 * fill)),
                    Color.black.opacity(0.02 + (0.02 * fill)),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .frostedGlass:
            return LinearGradient(
                colors: [
                    Color.white.opacity(0.06 + (0.02 * fill)),
                    Color(red: 0.55, green: 0.60, blue: 0.67).opacity(0.03 + (0.015 * fill)),
                    Color(red: 0.20, green: 0.22, blue: 0.27).opacity(0.20 + (0.05 * fill)),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .darkFrosted:
            return LinearGradient(
                colors: [
                    Color.white.opacity(0.05 + (0.03 * fill)),
                    Color(red: 0.12, green: 0.14, blue: 0.19).opacity(0.66 + (0.08 * fill)),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private func sectionStroke(for mode: MatchaAppearanceMode, extra: CGFloat) -> Color {
        switch mode {
        case .liquidGlass:
            return Color.white.opacity(0.10 + extra)
        case .frostedGlass:
            return Color.white.opacity(0.06 + extra)
        case .darkFrosted:
            return Color.white.opacity(0.04 + extra)
        }
    }
}

private struct MatchaSubtleCardModifier: ViewModifier {
    let corner: CGFloat
    let fillOpacity: CGFloat
    let strokeOpacity: CGFloat
    @AppStorage("matchaAppearanceMode") private var appearanceMode = MatchaAppearanceMode.darkFrosted.rawValue

    func body(content: Content) -> some View {
        let normalizedFill = max(0.0, min(fillOpacity, 1.0))
        let mode = MatchaChromeStyle.mode(from: appearanceMode)
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)

        return content
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(subtleBackground(for: mode, shape: shape, fill: normalizedFill))
            .overlay(
                shape.stroke(subtleStroke(for: mode, extra: strokeOpacity), lineWidth: 0.7)
            )
    }

    @ViewBuilder
    private func subtleBackground(for mode: MatchaAppearanceMode, shape: RoundedRectangle, fill: CGFloat) -> some View {
        switch mode {
        case .liquidGlass:
            shape
                .fill(Color.white.opacity(0.005))
                .glassEffect(in: shape)
                .overlay(
                    shape.fill(subtleGradient(for: mode, fill: fill))
                )
        case .frostedGlass, .darkFrosted:
            shape.fill(subtleGradient(for: mode, fill: fill))
        }
    }

    private func subtleGradient(for mode: MatchaAppearanceMode, fill: CGFloat) -> LinearGradient {
        switch mode {
        case .liquidGlass:
            return LinearGradient(
                colors: [
                    Color.white.opacity(0.028 + (0.008 * fill)),
                    Color.white.opacity(0.012 + (0.006 * fill)),
                    Color.black.opacity(0.018 + (0.02 * fill)),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .frostedGlass:
            return LinearGradient(
                colors: [
                    Color.white.opacity(0.035 + (0.015 * fill)),
                    Color(red: 0.22, green: 0.25, blue: 0.31).opacity(0.22 + (0.55 * fill)),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .darkFrosted:
            return LinearGradient(
                colors: [
                    Color.white.opacity(0.025 + (0.01 * fill)),
                    Color(red: 0.10, green: 0.11, blue: 0.15).opacity(0.48 + fill),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private func subtleStroke(for mode: MatchaAppearanceMode, extra: CGFloat) -> Color {
        switch mode {
        case .liquidGlass:
            return Color.white.opacity(0.09 + extra)
        case .frostedGlass:
            return Color.white.opacity(0.05 + extra)
        case .darkFrosted:
            return Color.white.opacity(0.03 + extra)
        }
    }
}

private struct MatchaAccessorySurfaceModifier: ViewModifier {
    let corner: CGFloat
    @AppStorage("matchaAppearanceMode") private var appearanceMode = MatchaAppearanceMode.darkFrosted.rawValue

    func body(content: Content) -> some View {
        let mode = MatchaChromeStyle.mode(from: appearanceMode)
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)

        content
            .background(background(for: mode, shape: shape))
            .overlay(shape.stroke(stroke(for: mode), lineWidth: 0.6))
    }

    @ViewBuilder
    private func background(for mode: MatchaAppearanceMode, shape: RoundedRectangle) -> some View {
        switch mode {
        case .liquidGlass:
            shape
                .fill(Color.white.opacity(0.012))
                .glassEffect(in: shape)
                .overlay(
                    shape.fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.04),
                                Color.white.opacity(0.012),
                                Color.black.opacity(0.01),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                )
        case .frostedGlass:
            shape.fill(Color.white.opacity(0.045))
        case .darkFrosted:
            shape.fill(Color.white.opacity(0.04))
        }
    }

    private func stroke(for mode: MatchaAppearanceMode) -> Color {
        switch mode {
        case .liquidGlass:
            return Color.white.opacity(0.13)
        case .frostedGlass:
            return Color.white.opacity(0.07)
        case .darkFrosted:
            return Color.white.opacity(0.08)
        }
    }
}

private struct MatchaGlassContainerModifier: ViewModifier {
    @AppStorage("matchaAppearanceMode") private var appearanceMode = MatchaAppearanceMode.darkFrosted.rawValue

    func body(content: Content) -> some View {
        if MatchaChromeStyle.mode(from: appearanceMode) == .liquidGlass {
            GlassEffectContainer(spacing: 10) {
                content
            }
        } else {
            content
        }
    }
}

private struct WindowAccessor: NSViewRepresentable {
    let onWindowAvailable: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                onWindowAvailable(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                onWindowAvailable(window)
            }
        }
    }
}

struct MatchaDashboardView: View {
    let soccerFeeds: [SoccerLeagueFeed]
    let cricketMatches: [CricketMatch]

    @Binding var currentTitle: String
    @Binding var currentGameID: String
    @Binding var currentGameState: String

    let refreshAction: () -> Void
    let clearPinnedAction: () -> Void
    let openPreferencesAction: () -> Void
    let quitAction: () -> Void

    @AppStorage("iptvM3UURL") private var iptvM3UURL = ""
    @AppStorage("iptvEPGURL") private var iptvEPGURL = ""
    @AppStorage("enableStreamedProvider") private var enableStreamedProvider = true
    @AppStorage("streamedBaseURL") private var streamedBaseURL = "https://streamed.st"
    @AppStorage("favoriteTeamsCsv") private var legacyFavoriteTeamsCsv = ""
    @AppStorage("favoriteSoccerCsv") private var favoriteSoccerCsv = ""
    @AppStorage("favoriteCricketCsv") private var favoriteCricketCsv = ""
    @AppStorage("favoriteCompetitionsCsv") private var favoriteCompetitionsCsv = ""
    @AppStorage(FavoriteSelectionsStore.storageKey) private var favoriteSelectionsJSON = ""
    @AppStorage("enableDemoMode") private var enableDemoMode = false
    @AppStorage("matchaAppearanceMode") private var appearanceMode = MatchaAppearanceMode.darkFrosted.rawValue

    @State private var selectedDetail: MatchDetailSelection?
    @State private var searchText: String = ""
    @State private var isSearchExpanded = false
    @State private var showRecentResults = false
    @State private var visibilityFilter: MatchVisibilityFilter = .all
    @AppStorage("matchaSelectedMatchID") private var persistedSelectedMatchID = ""
    @State private var hasRestoredPersistedSelection = false
    @State private var preloadedWatchOptionsByMatchID: [String: [IPTVResolver.MatchResolution]] = [:]
    @State private var watchPreloadInFlight: Set<String> = []
    @State private var watchPreloadCycle = 0
    @State private var menuWindow: NSWindow?
    @State private var detailWindow: NSWindow?
    @AppStorage("compactMode") private var compactMode = false
    private let turfGreen = Color(red: 0.19, green: 0.56, blue: 0.33)
    private let menuMinSize = CGSize(width: 336, height: 420)
    private let menuMaxSize = CGSize(width: 520, height: 920)
    private let detailMinSize = CGSize(width: 352, height: 460)
    private let detailMaxSize = CGSize(width: 488, height: 900)

    private var maxDisplayedMatches: Int {
        compactMode ? 30 : 20
    }

    private var chromeMode: MatchaAppearanceMode {
        MatchaChromeStyle.mode(from: appearanceMode)
    }

    private var soccerTerms: [String] {
        FavoriteSelectionsStore.teamTerms(
            json: favoriteSelectionsJSON,
            sport: .soccer,
            legacySoccerCsv: favoriteSoccerCsv,
            legacyCricketCsv: favoriteCricketCsv,
            legacyCombinedCsv: legacyFavoriteTeamsCsv
        )
    }

    private var cricketTerms: [String] {
        FavoriteSelectionsStore.teamTerms(
            json: favoriteSelectionsJSON,
            sport: .cricket,
            legacySoccerCsv: favoriteSoccerCsv,
            legacyCricketCsv: favoriteCricketCsv,
            legacyCombinedCsv: legacyFavoriteTeamsCsv
        )
    }

    private var competitionTerms: [String] {
        FavoriteSelectionsStore.competitionTerms(
            json: favoriteSelectionsJSON,
            legacyCsv: favoriteCompetitionsCsv
        )
    }

    private var hasFavoriteFilters: Bool {
        enableDemoMode || !(soccerTerms.isEmpty && cricketTerms.isEmpty && competitionTerms.isEmpty)
    }

    private var effectiveSoccerFeeds: [SoccerLeagueFeed] {
        enableDemoMode ? demoSoccerFeeds : soccerFeeds
    }

    private var effectiveCricketMatches: [CricketMatch] {
        enableDemoMode ? demoCricketMatches : cricketMatches
    }

    private var favoriteSoccerGames: [FavoriteSoccerGame] {
        if enableDemoMode {
            return effectiveSoccerFeeds.flatMap { feed in
                feed.games.map { game in
                    FavoriteSoccerGame(
                        id: "\(feed.leagueCode)-\(game.id)",
                        leagueCode: feed.leagueCode,
                        leagueTitle: feed.leagueTitle,
                        game: game
                    )
                }
            }
            .sorted { $0.game.date < $1.game.date }
        }

        let matches = effectiveSoccerFeeds.flatMap { feed -> [FavoriteSoccerGame] in
            feed.games.compactMap { game in
                let teamNames = game.competitions.first?.competitors?.compactMap {
                    $0.team?.displayName?.lowercased() ?? $0.team?.name?.lowercased()
                } ?? []

                let matchup = (game.shortName ?? game.name).lowercased()
                let leagueName = feed.leagueTitle.lowercased()

                let teamMatch = soccerTerms.isEmpty ? false : soccerTerms.contains { term in
                    teamNames.contains(where: { $0.contains(term) }) || matchup.contains(term)
                }

                let competitionMatch = competitionTerms.isEmpty ? false : competitionTerms.contains { term in
                    competitionTermMatches(term: term, in: [leagueName, matchup])
                }

                guard teamMatch || competitionMatch else { return nil }

                return FavoriteSoccerGame(
                    id: "\(feed.leagueCode)-\(game.id)",
                    leagueCode: feed.leagueCode,
                    leagueTitle: feed.leagueTitle,
                    game: game
                )
            }
        }

        return matches.sorted { $0.game.date < $1.game.date }
    }

    private var favoriteCricketGames: [CricketMatch] {
        if enableDemoMode {
            return effectiveCricketMatches.sorted { $0.startTimestamp < $1.startTimestamp }
        }

        return effectiveCricketMatches.filter { match in
            let teamNames = [match.team1Name.lowercased(), match.team2Name.lowercased()]
            let hasWomenSide = teamNames.contains(where: containsWomenKeyword)

            let haystack = [
                match.title,
                match.detail,
                match.team1Name,
                match.team2Name,
                match.seriesName,
                match.matchDesc,
            ]
            .joined(separator: " ")
            .lowercased()

            let teamMatch = cricketTerms.isEmpty ? false : cricketTerms.contains { term in
                let normalized = term.lowercased()
                let explicitWomen = containsWomenKeyword(normalized)

                if hasWomenSide && !explicitWomen {
                    return false
                }

                return teamNames.contains(where: { $0.contains(normalized) }) || haystack.contains(normalized)
            }

            let competitionMatch = competitionTerms.isEmpty ? false : competitionTerms.contains { term in
                competitionTermMatches(term: term, in: [haystack])
            }
            return teamMatch || competitionMatch
        }
        .sorted { $0.startTimestamp < $1.startTimestamp }
    }

    private struct UnifiedMatch: Identifiable {
        let id: String
        let sortDate: Date
        let isLive: Bool
        let soccer: FavoriteSoccerGame?
        let cricket: CricketMatch?
    }

    private struct MatchDisplaySnapshot {
        let visible: [UnifiedMatch]
        let primary: [UnifiedMatch]
        let recentCompleted: [UnifiedMatch]
        let liveCount: Int
    }

    private var allMatches: [UnifiedMatch] {
        let soccer: [UnifiedMatch] = favoriteSoccerGames.map { item in
            UnifiedMatch(
                id: "soccer-\(item.id)",
                sortDate: DashboardDateFormatters.iso.date(from: item.game.date) ?? .distantFuture,
                isLive: item.game.status.type.state == "in",
                soccer: item,
                cricket: nil
            )
        }

        let cricket: [UnifiedMatch] = favoriteCricketGames.map { match in
            UnifiedMatch(
                id: "cricket-\(match.id)",
                sortDate: Date(timeIntervalSince1970: Double(match.startTimestamp) / 1000.0),
                isLive: match.isLive,
                soccer: nil,
                cricket: match
            )
        }

        return soccer + cricket
    }

    private var displaySnapshot: MatchDisplaySnapshot {
        var live: [UnifiedMatch] = []
        var upcoming: [UnifiedMatch] = []
        var completedRecent: [UnifiedMatch] = []

        for match in allMatches {
            if matchIsLive(match) {
                live.append(match)
            } else if matchIsUpcoming(match) {
                upcoming.append(match)
            } else if isWithinRecentCompletedWindow(match.sortDate) {
                completedRecent.append(match)
            }
        }

        live.sort { $0.sortDate < $1.sortDate }
        upcoming.sort { $0.sortDate < $1.sortDate }
        completedRecent.sort { $0.sortDate > $1.sortDate }

        let visible: [UnifiedMatch]
        if visibilityFilter == .live {
            visible = Array(live.prefix(maxDisplayedMatches))
        } else {
            visible = Array((live + upcoming + completedRecent).prefix(maxDisplayedMatches))
        }

        var primary: [UnifiedMatch] = []
        var recentCompleted: [UnifiedMatch] = []
        var liveCount = 0

        for match in visible {
            if match.isLive { liveCount += 1 }
            if matchIsCompleted(match) {
                recentCompleted.append(match)
            } else {
                primary.append(match)
            }
        }

        return MatchDisplaySnapshot(
            visible: visible,
            primary: primary,
            recentCompleted: recentCompleted,
            liveCount: liveCount
        )
    }

    private var displayedMatches: [UnifiedMatch] {
        displaySnapshot.visible
    }

    private var primaryDisplayedMatches: [UnifiedMatch] {
        displaySnapshot.primary
    }

    private var recentCompletedDisplayedMatches: [UnifiedMatch] {
        displaySnapshot.recentCompleted
    }

    private var liveMatchesCount: Int {
        displaySnapshot.liveCount
    }

    private var visibleMatchCount: Int {
        primaryDisplayedMatches.count + (showRecentResults ? recentCompletedDisplayedMatches.count : 0)
    }

    private func matchIsLive(_ unified: UnifiedMatch) -> Bool {
        if let soccer = unified.soccer {
            return soccer.game.status.type.state == "in"
        }
        if let cricket = unified.cricket {
            return cricket.isLive
        }
        return false
    }

    private func matchIsUpcoming(_ unified: UnifiedMatch) -> Bool {
        if let soccer = unified.soccer {
            return soccer.game.status.type.state == "pre"
        }
        if let cricket = unified.cricket {
            return cricket.isUpcoming
        }
        return false
    }

    private func matchIsCompleted(_ unified: UnifiedMatch) -> Bool {
        !matchIsLive(unified) && !matchIsUpcoming(unified)
    }

    private func isWithinRecentCompletedWindow(_ date: Date) -> Bool {
        let cal = Calendar.current
        let startToday = cal.startOfDay(for: Date())
        guard let oldest = cal.date(byAdding: .day, value: -3, to: startToday) else {
            return false
        }
        return date >= oldest
    }

    private var allSearchableMatches: [UnifiedMatch] {
        let soccer: [UnifiedMatch] = effectiveSoccerFeeds.flatMap { feed in
            feed.games.map { game in
                UnifiedMatch(
                    id: "soccer-\(feed.leagueCode)-\(game.id)",
                    sortDate: DashboardDateFormatters.iso.date(from: game.date) ?? .distantFuture,
                    isLive: game.status.type.state == "in",
                    soccer: FavoriteSoccerGame(
                        id: "\(feed.leagueCode)-\(game.id)",
                        leagueCode: feed.leagueCode,
                        leagueTitle: feed.leagueTitle,
                        game: game
                    ),
                    cricket: nil
                )
            }
        }

        let cricket: [UnifiedMatch] = effectiveCricketMatches.map { match in
            UnifiedMatch(
                id: "cricket-\(match.id)",
                sortDate: Date(timeIntervalSince1970: Double(match.startTimestamp) / 1000.0),
                isLive: match.isLive,
                soccer: nil,
                cricket: match
            )
        }

        return (soccer + cricket).sorted { lhs, rhs in
            if lhs.isLive != rhs.isLive { return lhs.isLive }
            return lhs.sortDate < rhs.sortDate
        }
    }

    private var searchedMatches: [UnifiedMatch] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return [] }
        return Array(allSearchableMatches.filter { searchHaystack(for: $0).contains(query) }.prefix(10))
    }

    private var searchedCatalogItems: [FavoriteCatalogItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return [] }
        return Array(searchCatalog.filter { item in
            let haystack = "\(item.name) \(item.sport.rawValue) \(item.kind.rawValue) \(item.country ?? "")".lowercased()
            return haystack.contains(query)
        }.prefix(12))
    }

    private var searchCatalog: [FavoriteCatalogItem] {
        var items: [FavoriteCatalogItem] = baseSearchCatalog

        for feed in effectiveSoccerFeeds {
            items.append(FavoriteCatalogItem(kind: .competition, sport: .soccer, name: feed.leagueTitle, country: nil))
            for game in feed.games {
                let teams = game.competitions.first?.competitors?.compactMap { $0.team?.displayName ?? $0.team?.name } ?? []
                for team in teams where !team.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    items.append(FavoriteCatalogItem(kind: .team, sport: .soccer, name: team, country: nil))
                }
            }
        }

        for match in effectiveCricketMatches {
            if !match.seriesName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                items.append(FavoriteCatalogItem(kind: .competition, sport: .cricket, name: match.seriesName, country: nil))
            }
            for team in [match.team1Name, match.team2Name] where !team.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                items.append(FavoriteCatalogItem(kind: .team, sport: .cricket, name: team, country: nil))
            }
        }

        return FavoriteSelectionsStore.dedupe(items.map(\.selection)).map {
            FavoriteCatalogItem(kind: $0.kind, sport: $0.sport, name: $0.name, country: $0.country)
        }
    }

    private var baseSearchCatalog: [FavoriteCatalogItem] {
        let soccerCompetitions: [FavoriteCatalogItem] = [
            .init(kind: .competition, sport: .soccer, name: "Premier League", country: "England"),
            .init(kind: .competition, sport: .soccer, name: "UEFA Champions League", country: "Europe"),
            .init(kind: .competition, sport: .soccer, name: "UEFA Europa League", country: "Europe"),
            .init(kind: .competition, sport: .soccer, name: "La Liga", country: "Spain"),
            .init(kind: .competition, sport: .soccer, name: "Bundesliga", country: "Germany"),
            .init(kind: .competition, sport: .soccer, name: "Serie A", country: "Italy"),
            .init(kind: .competition, sport: .soccer, name: "Ligue 1", country: "France"),
            .init(kind: .competition, sport: .soccer, name: "MLS", country: "United States"),
            .init(kind: .competition, sport: .soccer, name: "FIFA World Cup", country: "International"),
            .init(kind: .competition, sport: .soccer, name: "UEFA European Championship", country: "Europe"),
        ]

        let soccerTeams: [FavoriteCatalogItem] = [
            .init(kind: .team, sport: .soccer, name: "Manchester City", country: "England"),
            .init(kind: .team, sport: .soccer, name: "Arsenal", country: "England"),
            .init(kind: .team, sport: .soccer, name: "Liverpool", country: "England"),
            .init(kind: .team, sport: .soccer, name: "Manchester United", country: "England"),
            .init(kind: .team, sport: .soccer, name: "Chelsea", country: "England"),
            .init(kind: .team, sport: .soccer, name: "Tottenham Hotspur", country: "England"),
            .init(kind: .team, sport: .soccer, name: "Real Madrid", country: "Spain"),
            .init(kind: .team, sport: .soccer, name: "Barcelona", country: "Spain"),
            .init(kind: .team, sport: .soccer, name: "Atletico Madrid", country: "Spain"),
            .init(kind: .team, sport: .soccer, name: "Bayern Munich", country: "Germany"),
            .init(kind: .team, sport: .soccer, name: "Borussia Dortmund", country: "Germany"),
            .init(kind: .team, sport: .soccer, name: "Paris Saint-Germain", country: "France"),
            .init(kind: .team, sport: .soccer, name: "Juventus", country: "Italy"),
            .init(kind: .team, sport: .soccer, name: "Inter Milan", country: "Italy"),
            .init(kind: .team, sport: .soccer, name: "AC Milan", country: "Italy"),
            .init(kind: .team, sport: .soccer, name: "Argentina", country: "Argentina"),
            .init(kind: .team, sport: .soccer, name: "Brazil", country: "Brazil"),
            .init(kind: .team, sport: .soccer, name: "England", country: "England"),
            .init(kind: .team, sport: .soccer, name: "France", country: "France"),
            .init(kind: .team, sport: .soccer, name: "Spain", country: "Spain"),
            .init(kind: .team, sport: .soccer, name: "Portugal", country: "Portugal"),
            .init(kind: .team, sport: .soccer, name: "Germany", country: "Germany"),
            .init(kind: .team, sport: .soccer, name: "Netherlands", country: "Netherlands"),
            .init(kind: .team, sport: .soccer, name: "United States", country: "United States"),
            .init(kind: .team, sport: .soccer, name: "Mexico", country: "Mexico"),
        ]

        let cricketCompetitions: [FavoriteCatalogItem] = [
            .init(kind: .competition, sport: .cricket, name: "IPL", country: "India"),
            .init(kind: .competition, sport: .cricket, name: "ICC T20 World Cup", country: "International"),
            .init(kind: .competition, sport: .cricket, name: "ICC Cricket World Cup", country: "International"),
        ]

        return soccerCompetitions + soccerTeams + cricketCompetitions
    }

    private var activeSelectedMatchID: String {
        selectedDetail?.id ?? persistedSelectedMatchID
    }

    private var hasAnyWatchProviderConfigured: Bool {
        let hasIPTV = !iptvM3UURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasIPTV || enableStreamedProvider
    }

    private var watchPreloadSignature: String {
        let matchIDs = displaySnapshot.visible
            .filter(isLiveOrUpcoming)
            .prefix(6)
            .map(\.id)
            .joined(separator: ",")
        return "\(iptvM3UURL)|\(iptvEPGURL)|\(enableStreamedProvider)|\(streamedBaseURL)|\(matchIDs)|\(watchPreloadCycle)"
    }

    private var selectionRestoreSignature: String {
        "\(persistedSelectedMatchID)|\(displaySnapshot.visible.map(\.id).joined(separator: ","))"
    }

    private var pinnedTitleRefreshSignature: String {
        let soccerSig = effectiveSoccerFeeds.flatMap { feed in
            feed.games.map { game in
                let competitors = game.competitions.first?.competitors ?? []
                let awayScore = competitors.count > 1 ? (competitors[1].score ?? "-") : "-"
                let homeScore = competitors.count > 0 ? (competitors[0].score ?? "-") : "-"
                return "\(feed.leagueCode):\(game.id):\(game.status.type.state):\(awayScore):\(homeScore)"
            }
        }.joined(separator: "|")

        let cricketSig = effectiveCricketMatches
            .map { "\($0.id):\($0.team1Score):\($0.team2Score):\($0.state):\($0.status)" }
            .joined(separator: "|")

        return "\(currentGameID)|\(soccerSig)|\(cricketSig)"
    }

    private var demoShowcaseItems: [(title: String, detail: String, status: String)] {
        [
            ("F1 • Bahrain GP", "VER vs NOR", "Lap 42/57"),
            ("NBA • Lakers v Warriors", "88 - 92", "Q4 06:18"),
            ("NFL • Chiefs v Bills", "17 - 14", "3rd 09:41"),
        ]
    }

    private var demoSoccerFeeds: [SoccerLeagueFeed] {
        [
            SoccerLeagueFeed(
                leagueCode: "FFWC",
                leagueTitle: "FIFA World Cup",
                games: [
                    demoSoccerEvent(
                        id: "demo-fifa-1",
                        date: "2026-06-18T19:00:00Z",
                        home: "Brazil",
                        away: "Argentina",
                        homeAbbr: "BRA",
                        awayAbbr: "ARG",
                        homeScore: "2",
                        awayScore: "1",
                        state: "in",
                        detail: "78'",
                        venue: "MetLife Stadium"
                    ),
                    demoSoccerEvent(
                        id: "demo-fifa-2",
                        date: "2026-06-19T18:00:00Z",
                        home: "France",
                        away: "England",
                        homeAbbr: "FRA",
                        awayAbbr: "ENG",
                        homeScore: "0",
                        awayScore: "0",
                        state: "pre",
                        detail: "Today • 6:00 PM",
                        venue: "SoFi Stadium"
                    ),
                ]
            ),
            SoccerLeagueFeed(
                leagueCode: "EPL",
                leagueTitle: "Premier League",
                games: [
                    demoSoccerEvent(
                        id: "demo-epl-1",
                        date: "2026-02-24T20:00:00Z",
                        home: "Arsenal",
                        away: "Manchester City",
                        homeAbbr: "ARS",
                        awayAbbr: "MCI",
                        homeScore: "3",
                        awayScore: "2",
                        state: "post",
                        detail: "FT",
                        venue: "Emirates Stadium"
                    ),
                ]
            ),
        ]
    }

    private var demoCricketMatches: [CricketMatch] {
        [
            CricketMatch(
                id: "demo-ipl-48",
                title: "Mumbai Indians vs Chennai Super Kings",
                detail: "48th Match",
                url: URL(string: "https://www.cricbuzz.com")!,
                team1Name: "Mumbai Indians",
                team2Name: "Chennai Super Kings",
                team1Short: "MI",
                team2Short: "CSK",
                team1Score: "184/6 (20)",
                team2Score: "172/8 (20)",
                team1InningsDetail: [],
                team2InningsDetail: [],
                team1Innings: ["184/6 (20)"],
                team2Innings: ["172/8 (20)"],
                state: "Complete",
                status: "MI won by 12 runs",
                seriesName: "Indian Premier League 2026",
                matchDesc: "48th Match",
                startTimestamp: 1771884000000
            ),
            CricketMatch(
                id: "demo-icc-21",
                title: "India vs South Africa",
                detail: "Super 8 • Match 21",
                url: URL(string: "https://www.cricbuzz.com")!,
                team1Name: "India",
                team2Name: "South Africa",
                team1Short: "IND",
                team2Short: "RSA",
                team1Score: "164/5 (18.2)",
                team2Score: "160/9 (20)",
                team1InningsDetail: [],
                team2InningsDetail: [],
                team1Innings: ["164/5 (18.2)"],
                team2Innings: ["160/9 (20)"],
                state: "In Progress",
                status: "IND need 1 from 10",
                seriesName: "ICC Men's T20 World Cup 2026",
                matchDesc: "Super 8 • Match 21 of 55",
                startTimestamp: 1771797600000
            ),
        ]
    }

    private func demoSoccerEvent(
        id: String,
        date: String,
        home: String,
        away: String,
        homeAbbr: String,
        awayAbbr: String,
        homeScore: String,
        awayScore: String,
        state: String,
        detail: String,
        venue: String
    ) -> Event {
        let statusType = type(
            state: state,
            completed: state == "post",
            detail: detail,
            shortDetail: detail
        )
        let status = Status(displayClock: nil, period: nil, type: statusType)
        let link = Links(
            language: "en-US",
            href: "https://www.espn.com",
            text: "Match Center",
            shortText: "Center",
            isExternal: true,
            isPremium: false
        )

        let homeTeam = Team(
            id: "\(id)-home",
            displayName: home,
            abbreviation: homeAbbr,
            name: home,
            logo: nil,
            links: [link],
            color: "1B5E20",
            alternateColor: "FFFFFF"
        )
        let awayTeam = Team(
            id: "\(id)-away",
            displayName: away,
            abbreviation: awayAbbr,
            name: away,
            logo: nil,
            links: [link],
            color: "0D47A1",
            alternateColor: "FFFFFF"
        )

        let competition = Competition(
            competitors: [
                Competitor(id: "\(id)-home-competitor", score: homeScore, order: 0, winner: nil, athlete: nil, team: homeTeam),
                Competitor(id: "\(id)-away-competitor", score: awayScore, order: 1, winner: nil, athlete: nil, team: awayTeam),
            ],
            status: status,
            situation: nil,
            highlights: nil,
            headlines: nil,
            venue: Venue(id: id, fullName: venue, address: VenueAddress(city: nil, state: nil)),
            notes: nil,
            broadcasts: [Broadcast(market: "National", names: ["ESPN", "Star Sports"])]
        )

        return Event(
            id: id,
            date: date,
            endDate: nil,
            name: "\(home) vs \(away)",
            shortName: "\(homeAbbr) vs \(awayAbbr)",
            competitions: [competition],
            weather: nil,
            status: status,
            links: [link],
            circuit: nil
        )
    }

    var body: some View {
        GeometryReader { proxy in
            leftPane
                .padding(0)
                .background(Color.clear)
                .frame(
                    width: max(proxy.size.width, 336),
                    height: max(proxy.size.height, 420),
                    alignment: .topLeading
                )
        }
        .frame(
            minWidth: 336,
            idealWidth: 388,
            maxWidth: .infinity,
            minHeight: 420,
            idealHeight: 540,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .background(MenuWindowConfigurator { window in
            if menuWindow !== window {
                menuWindow = window
            }
        })
        .popover(item: $selectedDetail, arrowEdge: .trailing) { detail in
            rightPane(for: detail, enableDataFetch: true)
                .frame(minWidth: detailMinSize.width, idealWidth: 412, maxWidth: detailMaxSize.width, minHeight: detailMinSize.height, idealHeight: 620, maxHeight: detailMaxSize.height)
                .padding(2)
                .background(WindowAccessor { window in
                    if detailWindow !== window {
                        detailWindow = window
                    }
                })
        }
        .task(id: watchPreloadSignature) {
            await preloadWatchOptionsForVisibleMatches()
        }
        .task(id: hasAnyWatchProviderConfigured) {
            guard hasAnyWatchProviderConfigured else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                if Task.isCancelled { break }
                watchPreloadCycle &+= 1
            }
        }
        .task {
            if !enableStreamedProvider {
                enableStreamedProvider = true
            }
        }
        .task(id: selectionRestoreSignature) {
            restorePersistedSelectionIfNeeded()
        }
        .task(id: pinnedTitleRefreshSignature) {
            refreshPinnedTitleIfNeeded()
        }
    }

    private var leftPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if isSearchExpanded {
                searchPanel
            }
            matchControls

            Group {
                if !hasFavoriteFilters {
                    Text("Set favorites in Settings -> Leagues/Favorites to show your matches here.")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 12)
                } else if displayedMatches.isEmpty {
                    Text(visibilityFilter == .live ? "No live matches for your selected teams/competitions." : "No matches found for your selected teams/competitions.")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 12)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: compactMode ? 5 : 6) {
                            ForEach(primaryDisplayedMatches) { unified in
                                if let item = unified.soccer {
                                    Button {
                                        if activeSelectedMatchID == "soccer-\(item.id)" {
                                            selectedDetail = nil
                                            persistedSelectedMatchID = ""
                                        } else {
                                            selectedDetail = .soccer(item)
                                            persistedSelectedMatchID = "soccer-\(item.id)"
                                        }
                                    } label: {
                                        SoccerMatchCard(
                                            item: item,
                                            isSelected: activeSelectedMatchID == "soccer-\(item.id)"
                                        )
                                    }
                                    .buttonStyle(.plain)
                                } else if let match = unified.cricket {
                                    Button {
                                        if activeSelectedMatchID == "cricket-\(match.id)" {
                                            selectedDetail = nil
                                            persistedSelectedMatchID = ""
                                        } else {
                                            selectedDetail = .cricket(match)
                                            persistedSelectedMatchID = "cricket-\(match.id)"
                                        }
                                    } label: {
                                        CricketMatchCard(
                                            match: match,
                                            isSelected: activeSelectedMatchID == "cricket-\(match.id)"
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }

                            if visibilityFilter == .all && !recentCompletedDisplayedMatches.isEmpty {
                                if showRecentResults {
                                    HStack(spacing: 8) {
                                        Rectangle()
                                            .fill(Color.white.opacity(0.14))
                                            .frame(height: 0.5)
                                        MatchaSectionHeading(title: "Recent Results")
                                        Rectangle()
                                            .fill(Color.white.opacity(0.14))
                                            .frame(height: 0.5)
                                        Button {
                                            withAnimation(.easeInOut(duration: 0.22)) {
                                                showRecentResults = false
                                            }
                                        } label: {
                                            Image(systemName: "chevron.up")
                                                .font(.system(size: 9.5, weight: .semibold))
                                        }
                                        .buttonStyle(MatchaMiniControlButtonStyle())
                                        .help("Hide recent results")
                                    }
                                    .padding(.top, 4)
                                    .padding(.bottom, 2)

                                    ForEach(recentCompletedDisplayedMatches) { unified in
                                        if let item = unified.soccer {
                                            Button {
                                                if activeSelectedMatchID == "soccer-\(item.id)" {
                                                    selectedDetail = nil
                                                    persistedSelectedMatchID = ""
                                                } else {
                                                    selectedDetail = .soccer(item)
                                                    persistedSelectedMatchID = "soccer-\(item.id)"
                                                }
                                            } label: {
                                                SoccerMatchCard(
                                                    item: item,
                                                    isSelected: activeSelectedMatchID == "soccer-\(item.id)"
                                                )
                                            }
                                            .buttonStyle(.plain)
                                        } else if let match = unified.cricket {
                                            Button {
                                                if activeSelectedMatchID == "cricket-\(match.id)" {
                                                    selectedDetail = nil
                                                    persistedSelectedMatchID = ""
                                                } else {
                                                    selectedDetail = .cricket(match)
                                                    persistedSelectedMatchID = "cricket-\(match.id)"
                                                }
                                            } label: {
                                                CricketMatchCard(
                                                    match: match,
                                                    isSelected: activeSelectedMatchID == "cricket-\(match.id)"
                                                )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                } else {
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.24)) {
                                            showRecentResults = true
                                        }
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: "clock.arrow.circlepath")
                                                .font(.system(size: 10.5, weight: .semibold))
                                            Text("Recent results (\(recentCompletedDisplayedMatches.count))")
                                                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                                                .lineLimit(1)
                                            Spacer(minLength: 4)
                                            Image(systemName: "chevron.down")
                                                .font(.system(size: 9.5, weight: .semibold))
                                        }
                                        .foregroundColor(.white.opacity(0.66))
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 6)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .fill(Color.white.opacity(0.03))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .stroke(Color.white.opacity(0.08), lineWidth: 0.6)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.top, 4)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.trailing, 2)
                        .padding(.bottom, 6)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .frame(maxHeight: .infinity)

            if enableDemoMode {
                demoShowcaseStrip
            }

            HStack(spacing: 10) {
                Button(action: refreshAction) {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 14, height: 14)
                }
                    .buttonStyle(MatchaMiniControlButtonStyle(prominent: true))
                    .help("Refresh")
                Button(action: clearPinnedAction) {
                    Image(systemName: "pin.slash")
                        .frame(width: 14, height: 14)
                }
                    .buttonStyle(MatchaMiniControlButtonStyle())
                    .help("Clear Pin")
                Spacer()
                Button(action: openPreferencesAction) {
                    Image(systemName: "gearshape")
                        .frame(width: 14, height: 14)
                }
                    .buttonStyle(MatchaMiniControlButtonStyle())
                    .help("Settings")
                Button(action: quitAction) {
                    Image(systemName: "power")
                        .frame(width: 14, height: 14)
                }
                    .buttonStyle(MatchaMiniControlButtonStyle())
                    .help("Quit")
            }
            .font(.system(size: 12, weight: .semibold))
            .controlSize(.small)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .matchaAccessorySurface(corner: 12)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .matchaGlassContainer()
        .matchaChromePanel()
        .overlay(alignment: .bottomTrailing) {
            WindowResizeHandle(window: menuWindow, minSize: menuMinSize, maxSize: menuMaxSize)
                .padding(.trailing, 2)
                .padding(.bottom, 2)
        }
        .onChange(of: visibilityFilter) { newValue in
            if newValue == .live {
                showRecentResults = false
            }
        }
    }

    private var demoShowcaseStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Demo Cross-Sport Preview")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 6) {
                ForEach(demoShowcaseItems, id: \.title) { item in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                        Text(item.detail)
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        Text(item.status)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(turfGreen)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.ultraThinMaterial.opacity(0.55))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.09), lineWidth: 0.8)
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func rightPane(for detail: MatchDetailSelection, enableDataFetch: Bool) -> some View {
        Group {
            switch detail {
            case let .soccer(item):
                SoccerInlineDetailPane(
                    item: item,
                    iptvM3UURL: iptvM3UURL,
                    iptvEPGURL: iptvEPGURL,
                    enableStreamedProvider: enableStreamedProvider,
                    streamedBaseURL: streamedBaseURL,
                    preloadedWatchOptions: preloadedWatchOptionsByMatchID["soccer-\(item.id)"] ?? [],
                    enableDataFetch: enableDataFetch,
                    onPin: {
                        currentTitle = displayText(for: item.game, league: item.leagueCode)
                        currentGameID = item.game.id
                        currentGameState = item.game.status.type.state
                    },
                    onClose: {
                        self.selectedDetail = nil
                        self.persistedSelectedMatchID = ""
                    }
                )
            case let .cricket(match):
                CricketInlineDetailPane(
                    match: match,
                    iptvM3UURL: iptvM3UURL,
                    iptvEPGURL: iptvEPGURL,
                    enableStreamedProvider: enableStreamedProvider,
                    streamedBaseURL: streamedBaseURL,
                    preloadedWatchOptions: preloadedWatchOptionsByMatchID["cricket-\(match.id)"] ?? [],
                    enableDataFetch: enableDataFetch,
                    onPin: { pinnedTitle in
                        currentTitle = pinnedTitle
                        currentGameID = "cricket:\(match.id)"
                        currentGameState = match.state.lowercased()
                    },
                    onClose: {
                        self.selectedDetail = nil
                        self.persistedSelectedMatchID = ""
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .matchaChromePanel()
        .overlay(alignment: .bottomTrailing) {
            WindowResizeHandle(window: detailWindow, minSize: detailMinSize, maxSize: detailMaxSize)
                .padding(.trailing, 2)
                .padding(.bottom, 2)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sportscourt.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(MatchaChromeStyle.primaryForeground(for: chromeMode))
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [turfGreen.opacity(0.20), Color.white.opacity(0.04)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .matchaAccessorySurface(corner: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text("Matcha")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(MatchaChromeStyle.primaryForeground(for: chromeMode))
            }

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSearchExpanded.toggle()
                    if !isSearchExpanded {
                        searchText = ""
                    }
                }
            } label: {
                Image(systemName: isSearchExpanded ? "xmark" : "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 26, height: 22)
            }
            .buttonStyle(MatchaMiniControlButtonStyle())
            .controlSize(.small)
            .help(isSearchExpanded ? "Close Search" : "Search & Add Favorites")
        }
    }

    private var searchPanel: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(MatchaChromeStyle.secondaryForeground(for: chromeMode))
                TextField(
                    "",
                    text: $searchText,
                    prompt: Text("Search matches, teams, competitions")
                        .foregroundColor(MatchaChromeStyle.tertiaryForeground(for: chromeMode))
                )
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(MatchaChromeStyle.primaryForeground(for: chromeMode))
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(MatchaChromeStyle.secondaryForeground(for: chromeMode))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .matchaAccessorySurface(corner: 10)

            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Search across matches, teams, and competitions.")
                        .font(.caption2)
                        .foregroundColor(MatchaChromeStyle.secondaryForeground(for: chromeMode))
            } else {
                if searchedMatches.isEmpty, searchedCatalogItems.isEmpty {
                    Text("No results")
                        .font(.caption2)
                        .foregroundColor(MatchaChromeStyle.secondaryForeground(for: chromeMode))
                } else {
                    if !searchedMatches.isEmpty {
                        MatchaSectionHeading(title: "Matches")
                        ForEach(searchedMatches) { unified in
                            searchMatchRow(unified)
                        }
                    }
                    if !searchedCatalogItems.isEmpty {
                        MatchaSectionHeading(title: "Favorites")
                            .padding(.top, searchedMatches.isEmpty ? 0 : 3)
                        ForEach(searchedCatalogItems) { item in
                            searchFavoriteRow(item)
                        }
                    }
                }
            }
        }
        .matchaSectionCard(corner: 10, fillOpacity: 0.34, strokeOpacity: 0.08)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var matchControls: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Text(visibilityFilter == .live ? "Live now" : "\(visibleMatchCount) matches")
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundColor(MatchaChromeStyle.secondaryForeground(for: chromeMode))
                if visibilityFilter == .all, !showRecentResults, !recentCompletedDisplayedMatches.isEmpty {
                    Text("\(recentCompletedDisplayedMatches.count) recent")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.70))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.10), lineWidth: 0.6)
                        )
                }
                Spacer(minLength: 6)
                Picker("", selection: $visibilityFilter) {
                    ForEach(MatchVisibilityFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 104)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .matchaAccessorySurface(corner: 10)
        }
    }

    private func containsWomenKeyword(_ value: String) -> Bool {
        ["women", "womens", "women's", "ladies", "female", "girls"].contains { value.contains($0) }
    }

    private func competitionTermMatches(term: String, in haystacks: [String]) -> Bool {
        let normalizedTerm = normalizedSearch(term)
        let termTokens = Set(normalizedTerm.split(separator: " ").map(String.init).filter { $0.count > 1 })
        guard !termTokens.isEmpty else { return false }

        for haystack in haystacks {
            let normalizedHaystack = normalizedSearch(haystack)

            if normalizedHaystack.contains(normalizedTerm) {
                return true
            }

            let hayTokens = Set(normalizedHaystack.split(separator: " ").map(String.init).filter { $0.count > 1 })
            let overlapCount = termTokens.intersection(hayTokens).count

            let minNeeded = termTokens.count <= 2 ? termTokens.count : max(2, Int(Double(termTokens.count) * 0.6))
            if overlapCount >= minNeeded {
                return true
            }
        }

        return false
    }

    private func normalizedSearch(_ value: String) -> String {
        let lowered = value.lowercased()
        let mapped = lowered.map { ch -> Character in
            if ch.isLetter || ch.isNumber {
                return ch
            }
            return " "
        }
        return String(mapped)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func searchHaystack(for unified: UnifiedMatch) -> String {
        if let soccer = unified.soccer {
            let teams = soccer.game.competitions.first?.competitors?.compactMap {
                $0.team?.displayName ?? $0.team?.name ?? $0.team?.abbreviation
            } ?? []
            let base = [soccer.leagueTitle, soccer.game.name, soccer.game.shortName].compactMap { $0 }
            return (base + teams)
                .joined(separator: " ")
                .lowercased()
        }

        if let cricket = unified.cricket {
            return [
                cricket.seriesName,
                cricket.team1Name,
                cricket.team2Name,
                cricket.matchDesc,
                cricket.status,
                cricket.title,
            ]
            .joined(separator: " ")
            .lowercased()
        }

        return ""
    }

    @ViewBuilder
    private func searchMatchRow(_ unified: UnifiedMatch) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(searchMatchTitle(unified))
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(searchMatchSubtitle(unified))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            MatchaProviderBadge(
                title: searchMatchSportLabel(unified),
                tint: searchMatchSportTint(unified)
            )
            if isFavoriteMatch(unified) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(turfGreen)
                    .font(.system(size: 12))
                    .help("Already in favorites")
            } else {
                Button {
                    addFavorites(from: unified)
                } label: {
                    Image(systemName: "star.badge.plus")
                }
                .buttonStyle(MatchaMiniControlButtonStyle())
                .controlSize(.mini)
                .help("Add teams and competition to favorites")
            }
            Button {
                openDetail(fromSearch: unified)
            } label: {
                Image(systemName: "arrow.right.circle")
            }
            .buttonStyle(MatchaMiniControlButtonStyle())
            .help("Open match details")
        }
        .matchaSubtleCard(corner: 8, fillOpacity: 0.02, strokeOpacity: 0.04)
    }

    @ViewBuilder
    private func searchFavoriteRow(_ item: FavoriteCatalogItem) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(searchFavoriteSubtitle(item))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            MatchaProviderBadge(
                title: searchFavoriteSportLabel(item),
                tint: searchFavoriteSportTint(item)
            )
            Text(item.kind == .team ? "Team" : "Competition")
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
            if isFavorited(item) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(turfGreen)
                    .font(.system(size: 12))
            } else {
                Button {
                    addFavorite(item)
                } label: {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(MatchaMiniControlButtonStyle())
                .help("Add to favorites")
            }
        }
        .matchaSubtleCard(corner: 8, fillOpacity: 0.02, strokeOpacity: 0.04)
    }

    private func openDetail(fromSearch unified: UnifiedMatch) {
        if let soccer = unified.soccer {
            selectedDetail = .soccer(soccer)
            persistedSelectedMatchID = "soccer-\(soccer.id)"
        } else if let cricket = unified.cricket {
            selectedDetail = .cricket(cricket)
            persistedSelectedMatchID = "cricket-\(cricket.id)"
        }
    }

    private func isFavoriteMatch(_ unified: UnifiedMatch) -> Bool {
        if let soccer = unified.soccer {
            return favoriteSoccerGames.contains(where: { $0.id == soccer.id })
        }
        if let cricket = unified.cricket {
            return favoriteCricketGames.contains(where: { $0.id == cricket.id })
        }
        return false
    }

    private func searchMatchTitle(_ unified: UnifiedMatch) -> String {
        if let soccer = unified.soccer {
            return displayText(for: soccer.game, league: soccer.leagueCode)
        }
        if let cricket = unified.cricket {
            return "\(cricket.team1Short) vs \(cricket.team2Short)"
        }
        return "Match"
    }

    private func searchMatchSubtitle(_ unified: UnifiedMatch) -> String {
        if let soccer = unified.soccer {
            return "Football • \(soccer.leagueTitle) • \(formattedTime(from: soccer.game.date))"
        }
        if let cricket = unified.cricket {
            let date = Date(timeIntervalSince1970: Double(cricket.startTimestamp) / 1000.0)
            return "Cricket • \(cricket.seriesName) • \(DashboardDateFormatters.cardDateTime.string(from: date))"
        }
        return ""
    }

    private func searchMatchSportLabel(_ unified: UnifiedMatch) -> String {
        if unified.soccer != nil {
            return "Football"
        }
        if unified.cricket != nil {
            return "Cricket"
        }
        return "Sport"
    }

    private func searchMatchSportTint(_ unified: UnifiedMatch) -> Color {
        if unified.soccer != nil {
            return Color(red: 0.20, green: 0.48, blue: 0.92)
        }
        if unified.cricket != nil {
            return turfGreen
        }
        return Color.white.opacity(0.3)
    }

    private func searchFavoriteSubtitle(_ item: FavoriteCatalogItem) -> String {
        let sport = searchFavoriteSportLabel(item)
        if let country = item.country, !country.isEmpty {
            return "\(sport) • \(country)"
        }
        return sport
    }

    private func searchFavoriteSportLabel(_ item: FavoriteCatalogItem) -> String {
        switch item.sport {
        case .soccer:
            return "Football"
        case .cricket:
            return "Cricket"
        }
    }

    private func searchFavoriteSportTint(_ item: FavoriteCatalogItem) -> Color {
        switch item.sport {
        case .soccer:
            return Color(red: 0.20, green: 0.48, blue: 0.92)
        case .cricket:
            return turfGreen
        }
    }

    private func favoritedIDs() -> Set<String> {
        Set(FavoriteSelectionsStore.decode(from: favoriteSelectionsJSON).map(\.id))
    }

    private func isFavorited(_ item: FavoriteCatalogItem) -> Bool {
        favoritedIDs().contains(item.id)
    }

    private func addFavorite(_ item: FavoriteCatalogItem) {
        var current = FavoriteSelectionsStore.decode(from: favoriteSelectionsJSON)
        current.append(item.selection)
        favoriteSelectionsJSON = FavoriteSelectionsStore.encode(current)
    }

    private func addFavorites(from unified: UnifiedMatch) {
        var additions: [FavoriteSelection] = []
        if let soccer = unified.soccer {
            additions.append(FavoriteSelection(kind: .competition, sport: .soccer, name: soccer.leagueTitle, country: nil))
            let teams = soccer.game.competitions.first?.competitors?.compactMap { $0.team?.displayName ?? $0.team?.name } ?? []
            additions.append(contentsOf: teams.map { FavoriteSelection(kind: .team, sport: .soccer, name: $0, country: nil) })
        }
        if let cricket = unified.cricket {
            additions.append(FavoriteSelection(kind: .competition, sport: .cricket, name: cricket.seriesName, country: nil))
            additions.append(FavoriteSelection(kind: .team, sport: .cricket, name: cricket.team1Name, country: nil))
            additions.append(FavoriteSelection(kind: .team, sport: .cricket, name: cricket.team2Name, country: nil))
        }
        var current = FavoriteSelectionsStore.decode(from: favoriteSelectionsJSON)
        current.append(contentsOf: additions.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        favoriteSelectionsJSON = FavoriteSelectionsStore.encode(current)
    }

    private func restorePersistedSelectionIfNeeded() {
        guard !hasRestoredPersistedSelection else { return }
        guard selectedDetail == nil else {
            hasRestoredPersistedSelection = true
            return
        }
        guard !persistedSelectedMatchID.isEmpty else {
            hasRestoredPersistedSelection = true
            return
        }

        if let restored = detailSelection(for: persistedSelectedMatchID) {
            selectedDetail = restored
        } else if !displayedMatches.contains(where: { $0.id == persistedSelectedMatchID }) {
            persistedSelectedMatchID = ""
        }
        hasRestoredPersistedSelection = true
    }

    private func refreshPinnedTitleIfNeeded() {
        guard !currentGameID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        if currentGameID.hasPrefix("cricket:") {
            let matchID = String(currentGameID.dropFirst("cricket:".count))
            guard let liveMatch = effectiveCricketMatches.first(where: { $0.id == matchID }) else { return }
            currentTitle = liveMatch.menubarText
            currentGameState = liveMatch.state.lowercased()
            return
        }

        for feed in effectiveSoccerFeeds {
            if let game = feed.games.first(where: { $0.id == currentGameID }) {
                currentTitle = displayText(for: game, league: feed.leagueCode)
                currentGameState = game.status.type.state
                return
            }
        }
    }

    private func detailSelection(for unifiedID: String) -> MatchDetailSelection? {
        guard let unified = displayedMatches.first(where: { $0.id == unifiedID }) else { return nil }
        if let soccer = unified.soccer { return .soccer(soccer) }
        if let cricket = unified.cricket { return .cricket(cricket) }
        return nil
    }

    private func isLiveOrUpcoming(_ unified: UnifiedMatch) -> Bool {
        if let soccer = unified.soccer {
            let state = soccer.game.status.type.state.lowercased()
            return state == "in" || state == "pre"
        }
        if let cricket = unified.cricket {
            return cricket.isLive || cricket.isUpcoming
        }
        return false
    }

    private func preloadWatchOptionsForVisibleMatches() async {
        guard hasAnyWatchProviderConfigured else {
            await MainActor.run {
                preloadedWatchOptionsByMatchID = [:]
                watchPreloadInFlight = []
            }
            return
        }

        let visibleLiveOrUpcoming = Array(displaySnapshot.visible.filter(isLiveOrUpcoming).prefix(6))
        let targetIDs = Set(visibleLiveOrUpcoming.map(\.id))
        await MainActor.run {
            preloadedWatchOptionsByMatchID = preloadedWatchOptionsByMatchID.filter { targetIDs.contains($0.key) }
            watchPreloadInFlight = watchPreloadInFlight.intersection(targetIDs)
        }

        let pendingMatches = await MainActor.run { () -> [UnifiedMatch] in
            let pending = visibleLiveOrUpcoming.filter { unified in
                preloadedWatchOptionsByMatchID[unified.id] == nil && !watchPreloadInFlight.contains(unified.id)
            }
            for unified in pending {
                _ = watchPreloadInFlight.insert(unified.id)
            }
            return pending
        }

        guard !pendingMatches.isEmpty else { return }

        var resolvedPairs: [(String, [IPTVResolver.MatchResolution])] = []
        await withTaskGroup(of: (String, [IPTVResolver.MatchResolution]).self) { group in
            for unified in pendingMatches {
                group.addTask {
                    let resolved = await resolveWatchOptions(for: unified)
                    return (unified.id, resolved)
                }
            }

            for await pair in group {
                resolvedPairs.append(pair)
            }
        }

        await MainActor.run {
            for (id, resolved) in resolvedPairs {
                preloadedWatchOptionsByMatchID[id] = resolved
                watchPreloadInFlight.remove(id)
            }
        }
    }

    private func resolveWatchOptions(for unified: UnifiedMatch) async -> [IPTVResolver.MatchResolution] {
        guard hasAnyWatchProviderConfigured else { return [] }

        let m3u = iptvM3UURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let epg = effectiveEPGURL
        var query: IPTVResolver.MatchQuery?

        if let soccer = unified.soccer {
            let competitors = soccer.game.competitions.first?.competitors ?? []
            let away = competitors.count > 1 ? competitors[1].team : nil
            let home = competitors.count > 0 ? competitors[0].team : nil
            let matchDate = DashboardDateFormatters.isoWithFractional.date(from: soccer.game.date)
                ?? DashboardDateFormatters.iso.date(from: soccer.game.date)
                ?? Date()
            let channels = Array(Set((soccer.game.competitions.first?.broadcasts ?? []).flatMap { $0.names ?? [] })).sorted()
            query = IPTVResolver.MatchQuery(
                sport: "soccer",
                league: soccer.leagueTitle,
                homeTeam: home?.displayName ?? home?.name ?? "Home",
                awayTeam: away?.displayName ?? away?.name ?? "Away",
                startDate: matchDate,
                isLive: soccer.game.status.type.state.lowercased() == "in",
                isUpcoming: soccer.game.status.type.state.lowercased() == "pre",
                broadcastHints: channels
            )
        } else if let cricket = unified.cricket {
            query = IPTVResolver.MatchQuery(
                sport: "cricket",
                league: cricket.seriesName,
                homeTeam: cricket.team1Name,
                awayTeam: cricket.team2Name,
                startDate: Date(timeIntervalSince1970: Double(cricket.startTimestamp) / 1000.0),
                isLive: cricket.isLive,
                isUpcoming: cricket.isUpcoming,
                broadcastHints: []
            )
        }

        guard let query else { return [] }

        var merged: [IPTVResolver.MatchResolution] = []
        if enableStreamedProvider {
            let streamedMatches = await StreamedResolver.resolveMatchStreams(
                query: query,
                config: .init(enabled: true, baseURLString: streamedBaseURL),
                limit: 6
            )
            merged.append(contentsOf: streamedMatches)
        }
        if !m3u.isEmpty {
            let iptvMatches = await IPTVResolver.shared.resolveMatchStreams(
                query: query,
                m3uURLString: m3u,
                epgURLString: epg,
                limit: 6
            )
            merged.append(contentsOf: iptvMatches)
        }
        return dedupeMatchOptions(merged, limit: 8)
    }

    private func dedupeMatchOptions(_ options: [IPTVResolver.MatchResolution], limit: Int) -> [IPTVResolver.MatchResolution] {
        var seen: Set<String> = []
        var out: [IPTVResolver.MatchResolution] = []
        for option in options {
            let key = "\(option.streamURL.absoluteString)|\(option.channelName)"
            if seen.contains(key) { continue }
            seen.insert(key)
            out.append(option)
            if out.count >= limit { break }
        }
        return out
    }

    private var effectiveEPGURL: String? {
        let epg = iptvEPGURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !epg.isEmpty { return epg }

        let m3u = iptvM3UURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !m3u.isEmpty else { return nil }
        if m3u.contains("/m3u") {
            return m3u.replacingOccurrences(of: "/m3u", with: "/epg")
        }
        if m3u.lowercased().hasSuffix(".m3u") {
            return String(m3u.dropLast(4)) + "/epg"
        }
        return nil
    }
}

private enum MatchDetailSelection: Identifiable {
    case soccer(FavoriteSoccerGame)
    case cricket(CricketMatch)

    var id: String {
        switch self {
        case let .soccer(item): return "soccer-\(item.id)"
        case let .cricket(match): return "cricket-\(match.id)"
        }
    }
}

private enum CricketDetailTab: Hashable {
    case overview
    case scorecard
    case standings
}

private enum SoccerDetailTab: Hashable {
    case overview
    case broadcast
    case standings
}

private enum MatchVisibilityFilter: String, CaseIterable, Identifiable {
    case all
    case live

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "All"
        case .live: return "Live"
        }
    }
}

private struct DetailPlaceholderView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "list.bullet.rectangle.portrait")
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            Text("Select a match")
                .font(.headline)
            Text("Tap any card on the left to view details here.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private extension View {
    func matchaChromePanel(corner: CGFloat = 14) -> some View {
        modifier(MatchaChromePanelModifier(corner: corner))
    }

    func matchaSectionCard(corner: CGFloat = 9, fillOpacity: CGFloat = 0.46, strokeOpacity: CGFloat = 0.07) -> some View {
        modifier(MatchaSectionCardModifier(corner: corner, fillOpacity: fillOpacity, strokeOpacity: strokeOpacity))
    }

    func matchaSubtleCard(corner: CGFloat = 9, fillOpacity: CGFloat = 0.045, strokeOpacity: CGFloat = 0.06) -> some View {
        modifier(MatchaSubtleCardModifier(corner: corner, fillOpacity: fillOpacity, strokeOpacity: strokeOpacity))
    }

    func matchaAccessorySurface(corner: CGFloat = 10) -> some View {
        modifier(MatchaAccessorySurfaceModifier(corner: corner))
    }

    func matchaGlassContainer() -> some View {
        modifier(MatchaGlassContainerModifier())
    }
}

private enum MatchaImageCache {
    private static let cache = NSCache<NSString, NSImage>()

    static func image(for localURL: URL) -> NSImage? {
        let key = localURL.path as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let image = NSImage(contentsOf: localURL) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}

private struct SoccerMatchCard: View {
    let item: FavoriteSoccerGame
    let isSelected: Bool
    @AppStorage("compactMode") private var compactMode = false

    var body: some View {
        let corner: CGFloat = compactMode ? 11 : 12
        let cardShape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        let game = item.game
        let competition = game.competitions.first
        let teams = competition?.competitors ?? []

        let away = teams.count > 1 ? teams[1] : nil
        let home = teams.count > 0 ? teams[0] : nil

        let awayPrimary = accentColor(fromHex: away?.team?.color, fallback: Color(red: 0.18, green: 0.42, blue: 0.84))
        let awaySecondary = accentColor(fromHex: away?.team?.alternateColor, fallback: awayPrimary)
        let homePrimary = accentColor(fromHex: home?.team?.color, fallback: Color(red: 0.78, green: 0.30, blue: 0.24))
        let homeSecondary = accentColor(fromHex: home?.team?.alternateColor, fallback: homePrimary)

        VStack(alignment: .leading, spacing: compactMode ? 3 : 4) {
            HStack(spacing: 8) {
                Text(item.leagueTitle)
                    .font(.system(size: 10.2, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.74))
                    .lineLimit(1)
                Spacer()
                Text(soccerDateLine(for: game))
                    .font(.system(size: 10.1, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.64))
                    .lineLimit(1)
            }

            HStack(spacing: compactMode ? 10 : 11) {
                soccerColumn(
                    team: away?.team,
                    score: scorePlaceholder(for: game, teamScore: away?.score, side: .away),
                    alignment: .leading
                )

                VStack(spacing: 1.5) {
                    Text(soccerCenterPrimary(for: game))
                        .font(.system(size: 9.8, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.76))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    if let secondary = soccerCenterSecondary(for: game) {
                        Text(secondary)
                            .font(.system(size: 9.8, weight: .medium, design: .rounded).monospacedDigit())
                            .foregroundColor(.white.opacity(0.60))
                            .lineLimit(1)
                    }
                }
                .frame(width: 74)

                soccerColumn(
                    team: home?.team,
                    score: scorePlaceholder(for: game, teamScore: home?.score, side: .home),
                    alignment: .trailing
                )
            }
        }
        .padding(.horizontal, compactMode ? 8 : 10)
        .padding(.vertical, compactMode ? 7 : 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            cardShape
                .fill(Color(red: 0.10, green: 0.115, blue: 0.15).opacity(0.96))
                .overlay(
                    LinearGradient(
                        colors: [
                            awayPrimary.opacity(0.22),
                            awaySecondary.opacity(0.08),
                            Color.clear,
                            homeSecondary.opacity(0.08),
                            homePrimary.opacity(0.20),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .overlay(
                    cardShape
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.04), Color.black.opacity(0.06)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
                .overlay(alignment: .leading) {
                    Circle()
                        .fill(awayPrimary.opacity(0.14))
                        .frame(width: 112, height: 112)
                        .blur(radius: 24)
                        .offset(x: -22, y: -8)
                        .allowsHitTesting(false)
                }
                .overlay(alignment: .trailing) {
                    Circle()
                        .fill(homePrimary.opacity(0.14))
                        .frame(width: 112, height: 112)
                        .blur(radius: 24)
                        .offset(x: 22, y: -8)
                        .allowsHitTesting(false)
                }
        )
        .clipShape(cardShape)
        .overlay(
            cardShape
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.45) : Color.white.opacity(0.06), lineWidth: isSelected ? 1.0 : 0.6)
        )
        .shadow(color: .black.opacity(isSelected ? 0.09 : 0.03), radius: isSelected ? 3 : 1.6, y: 1)
    }

    private enum Side {
        case away
        case home
    }

    @ViewBuilder
    private func soccerColumn(team: Team?, score: String, alignment: HorizontalAlignment) -> some View {
        let scoreParts = splitSoccerScore(score)

        VStack(alignment: alignment, spacing: 2) {
            Text(scoreParts.primary)
                .font(.system(size: compactMode ? 27 : 30, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if let meta = scoreParts.meta {
                Text(meta)
                    .font(.system(size: 10, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundColor(.white.opacity(0.58))
                    .lineLimit(1)
            }
            HStack(spacing: 6) {
                if alignment == .leading {
                    TeamLogo(urlString: team?.logo, fallback: team?.abbreviation ?? "?")
                }
                Text(team?.abbreviation ?? team?.displayName ?? "Team")
                    .font(.system(size: 11.8, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.88))
                    .lineLimit(1)
                if alignment == .trailing {
                    TeamLogo(urlString: team?.logo, fallback: team?.abbreviation ?? "?")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }

    private func scorePlaceholder(for game: Event, teamScore: String?, side: Side) -> String {
        if let teamScore, !teamScore.isEmpty {
            return teamScore
        }

        if game.status.type.state == "pre" {
            return side == .away ? formattedTime(from: game.date) : "-"
        }

        return "-"
    }

    private func splitSoccerScore(_ score: String) -> (primary: String, meta: String?) {
        let trimmed = score.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ("-", nil) }

        if let open = trimmed.firstIndex(of: "("),
           let close = trimmed[open...].firstIndex(of: ")"),
           open < close
        {
            let primary = trimmed[..<open].trimmingCharacters(in: .whitespacesAndNewlines)
            let inside = trimmed[trimmed.index(after: open)..<close]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (primary.isEmpty ? trimmed : primary, inside.isEmpty ? nil : inside)
        }

        if trimmed.count > 8, trimmed.contains(":") {
            return ("-", trimmed)
        }

        if trimmed.count > 9 {
            let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            if parts.count == 2 {
                return (String(parts[0]), String(parts[1]))
            }
        }

        return (trimmed, nil)
    }

    private func soccerDateLine(for game: Event) -> String {
        let state = game.status.type.state.lowercased()
        let clock = game.status.displayClock?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let kickoff = cardDateTime(fromISO: game.date)

        if state == "in" {
            if !clock.isEmpty {
                return "Live • \(clock)"
            }
            return "Live"
        }
        if state == "pre" {
            return kickoff
        }
        return kickoff
    }

    private func soccerCenterPrimary(for game: Event) -> String {
        let state = game.status.type.state.lowercased()
        if state == "in" {
            return game.status.displayClock?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? (game.status.displayClock ?? "Live")
                : "Live"
        }
        if state == "pre" {
            return "Upcoming"
        }
        if state == "post" || game.status.type.completed {
            return cleanedSoccerResult(for: game)
        }
        return "Match"
    }

    private func soccerCenterSecondary(for game: Event) -> String? {
        let state = game.status.type.state.lowercased()
        if state == "in" {
            let clock = game.status.displayClock?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return clock.isEmpty ? nil : "Live"
        }
        if state == "pre" {
            return "Starts Soon"
        }
        if state == "post" || game.status.type.completed {
            return "Final"
        }
        return nil
    }

    private func cleanedSoccerResult(for game: Event) -> String {
        let raw = (game.status.type.shortDetail ?? game.status.type.detail ?? "")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "Final" }

        let cleaned = raw
            .replacingOccurrences(of: #"^(?i)\s*(result|results|ft|full time)\s*([•:\-]\s*)?"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Final" : cleaned
    }

    private func cardDateTime(fromISO iso: String) -> String {
        let date = DashboardDateFormatters.isoWithFractional.date(from: iso) ?? DashboardDateFormatters.iso.date(from: iso)
        guard let date else { return formattedDate(from: iso) + " • " + formattedTime(from: iso) }
        return DashboardDateFormatters.cardDateTime.string(from: date)
    }

    private func accentColor(fromHex hex: String?, fallback: Color) -> Color {
        Color(hex: hex) ?? fallback
    }
}

private struct SoccerTeamLine: View {
    let team: Team?

    var body: some View {
        HStack(spacing: 8) {
            TeamLogo(urlString: team?.logo, fallback: team?.abbreviation ?? "?")
            Text(team?.abbreviation ?? team?.displayName ?? "Team")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
                .lineLimit(1)
        }
    }
}

private struct TeamLogo: View {
    let urlString: String?
    let fallback: String
    @State private var resolvedURL: URL?

    var body: some View {
        Group {
            if let resolvedURL, resolvedURL.isFileURL, let localImage = MatchaImageCache.image(for: resolvedURL) {
                Image(nsImage: localImage)
                    .resizable()
                    .scaledToFit()
                    .padding(3.2)
                    .background(Circle().fill(.white.opacity(0.97)))
                    .frame(width: 19, height: 19)
            } else if let resolvedURL {
                AsyncImage(url: resolvedURL) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFit()
                            .padding(3.2)
                            .background(Circle().fill(.white.opacity(0.97)))
                    default:
                        fallbackBadge
                    }
                }
                .frame(width: 19, height: 19)
            } else {
                fallbackBadge
            }
        }
        .task(id: urlString) {
            await resolveSourceURL()
        }
    }

    @MainActor
    private func resolveSourceURL() async {
        guard let urlString,
              let remoteURL = URL(string: urlString)
        else {
            resolvedURL = nil
            return
        }

        if let cached = SoccerLogoCache.existingLocalURL(for: remoteURL) {
            resolvedURL = cached
            return
        }

        resolvedURL = remoteURL
        await SoccerLogoCache.downloadAndCacheIfNeeded(remoteURL)

        if let cached = SoccerLogoCache.existingLocalURL(for: remoteURL) {
            resolvedURL = cached
        }
    }

    private var fallbackBadge: some View {
        Circle()
            .fill(.white.opacity(0.94))
            .overlay(
                Text(String(fallback.prefix(3)).uppercased())
                    .font(.system(size: 8.5, weight: .bold, design: .rounded))
                    .foregroundColor(.black.opacity(0.9))
            )
            .frame(width: 19, height: 19)
    }
}

private enum SoccerLogoCache {
    private static let directoryURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let dir = appSupport.appendingPathComponent("Matcha", isDirectory: true)
            .appendingPathComponent("SoccerLogoCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func existingLocalURL(for remoteURL: URL) -> URL? {
        let local = localURL(for: remoteURL)
        return FileManager.default.fileExists(atPath: local.path) ? local : nil
    }

    static func downloadAndCacheIfNeeded(_ remoteURL: URL) async {
        if existingLocalURL(for: remoteURL) != nil {
            return
        }

        var request = URLRequest(url: remoteURL)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode), !data.isEmpty else {
                return
            }
            try data.write(to: localURL(for: remoteURL), options: .atomic)
        } catch {
            return
        }
    }

    private static func localURL(for remoteURL: URL) -> URL {
        let hash = stableHash(remoteURL.absoluteString)
        let ext = remoteURL.pathExtension.isEmpty ? "img" : remoteURL.pathExtension
        return directoryURL.appendingPathComponent("logo_\(hash).\(ext)")
    }

    private static func stableHash(_ input: String) -> String {
        var value: UInt64 = 5381
        for byte in input.utf8 {
            value = ((value << 5) &+ value) &+ UInt64(byte)
        }
        return String(value, radix: 16)
    }
}

private struct StatusChip: View {
    let text: String

    var body: some View {
        Text(text.isEmpty ? "-" : text)
            .font(.system(size: 10.5, weight: .medium, design: .rounded))
            .foregroundColor(.white.opacity(0.82))
            .padding(.horizontal, 6.5)
            .padding(.vertical, 1.5)
            .background(Color.white.opacity(0.09), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.14), lineWidth: 0.55)
            )
            .lineLimit(1)
    }
}

private struct MatchaMiniControlButtonStyle: ButtonStyle {
    var prominent = false
    @AppStorage("matchaAppearanceMode") private var appearanceMode = MatchaAppearanceMode.darkFrosted.rawValue

    func makeBody(configuration: Configuration) -> some View {
        let mode = MatchaChromeStyle.mode(from: appearanceMode)
        configuration.label
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundColor(prominent ? .white : MatchaChromeStyle.primaryForeground(for: mode))
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(backgroundView(for: mode, pressed: configuration.isPressed))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(borderColor(for: mode), lineWidth: 0.6)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
    }

    @ViewBuilder
    private func backgroundView(for mode: MatchaAppearanceMode, pressed: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)

        if prominent {
            shape
                .fill(Color.accentColor.opacity(pressed ? 0.62 : 0.80))
        } else {
            switch mode {
            case .liquidGlass:
                shape
                    .fill(Color.white.opacity(0.01))
                    .glassEffect(in: shape)
                    .overlay(
                        shape.fill(Color.white.opacity(pressed ? 0.05 : 0.02))
                    )
            case .frostedGlass:
                shape
                    .fill(Color.white.opacity(pressed ? 0.10 : 0.07))
            case .darkFrosted:
                shape
                    .fill(Color.white.opacity(pressed ? 0.09 : 0.06))
            }
        }
    }

    private func borderColor(for mode: MatchaAppearanceMode) -> Color {
        if prominent {
            return Color.accentColor.opacity(0.30)
        }

        switch mode {
        case .liquidGlass:
            return Color.white.opacity(0.12)
        case .frostedGlass:
            return Color.white.opacity(0.10)
        case .darkFrosted:
            return Color.white.opacity(0.08)
        }
    }
}

private struct MatchaProviderBadge: View {
    let title: String
    let tint: Color
    @AppStorage("matchaAppearanceMode") private var appearanceMode = MatchaAppearanceMode.darkFrosted.rawValue

    init(source: String) {
        self.title = source == "streamed" ? "Streamed" : "IPTV"
        self.tint = source == "streamed"
            ? Color(red: 0.39, green: 0.58, blue: 0.98)
            : Color(red: 0.24, green: 0.72, blue: 0.50)
    }

    init(title: String, tint: Color) {
        self.title = title
        self.tint = tint
    }

    var body: some View {
        let mode = MatchaChromeStyle.mode(from: appearanceMode)
        Text(title)
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundColor(MatchaChromeStyle.primaryForeground(for: mode).opacity(0.86))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.16)))
            .overlay(
                Capsule()
                    .stroke(tint.opacity(0.28), lineWidth: 0.5)
            )
    }
}

private struct MatchaSectionHeading: View {
    let title: String
    @AppStorage("matchaAppearanceMode") private var appearanceMode = MatchaAppearanceMode.darkFrosted.rawValue

    var body: some View {
        let mode = MatchaChromeStyle.mode(from: appearanceMode)
        Text(title)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundColor(MatchaChromeStyle.secondaryForeground(for: mode))
            .tracking(0.1)
    }
}

private struct WindowResizeHandle: View {
    weak var window: NSWindow?
    let minSize: CGSize
    let maxSize: CGSize

    @State private var initialFrame: CGRect?

    var body: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundColor(.white.opacity(0.58))
            .frame(width: 22, height: 22)
            .background(Circle().fill(Color.black.opacity(0.16)))
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.6)
            )
            .contentShape(Rectangle())
            .help("Resize")
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard let window else { return }
                        let startFrame = initialFrame ?? window.frame
                        if initialFrame == nil {
                            initialFrame = startFrame
                        }

                        let proposedWidth = min(max(startFrame.width + value.translation.width, minSize.width), maxSize.width)
                        let proposedHeight = min(max(startFrame.height - value.translation.height, minSize.height), maxSize.height)
                        let newOrigin = CGPoint(
                            x: startFrame.origin.x,
                            y: startFrame.maxY - proposedHeight
                        )
                        let newFrame = CGRect(origin: newOrigin, size: CGSize(width: proposedWidth, height: proposedHeight))
                        window.setFrame(newFrame, display: true)
                    }
                    .onEnded { _ in
                        initialFrame = nil
                    }
            )
    }
}

private struct CricketMatchCard: View {
    let match: CricketMatch
    let isSelected: Bool
    @AppStorage("compactMode") private var compactMode = false

    var body: some View {
        let corner: CGFloat = compactMode ? 11 : 12
        let cardShape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        let leftPalette = cricketTeamPalette(for: match.team1Name, fallback: (Color(red: 0.18, green: 0.42, blue: 0.84), Color(red: 0.30, green: 0.58, blue: 0.96)))
        let rightPalette = cricketTeamPalette(for: match.team2Name, fallback: (Color(red: 0.21, green: 0.70, blue: 0.44), Color(red: 0.45, green: 0.82, blue: 0.58)))
        let leftTint = leftPalette.primary
        let rightTint = rightPalette.primary

        VStack(alignment: .leading, spacing: compactMode ? 3 : 4) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(match.seriesName.isEmpty ? "Cricket" : match.seriesName)
                        .font(.system(size: 10.2, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.74))
                        .lineLimit(1)
                }
                Spacer()
            }

            HStack(spacing: 8) {
                Text(cricketHeaderLeading(for: match))
                    .font(.system(size: 10.1, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(match.isLive ? 0.88 : 0.70))
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(cricketHeaderTrailing(for: match))
                    .font(.system(size: 10.1, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.62))
                    .lineLimit(1)
            }

            HStack(spacing: compactMode ? 10 : 11) {
                cricketColumn(
                    short: match.team1Short,
                    name: match.team1Name,
                    score: match.team1Score.isEmpty ? "-" : match.team1Score,
                    tint: leftTint,
                    alignment: .leading
                )

                VStack(spacing: 2) {
                    Text(fixtureStageLine(for: match))
                        .font(.system(size: 9.9, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.76))
                        .lineLimit(1)
                        .multilineTextAlignment(.center)
                    if let subline = cardSubline(for: match) {
                        Text(subline)
                            .font(.system(size: 9.4, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.60))
                            .lineLimit(1)
                    }
                }
                .frame(width: 90)

                cricketColumn(
                    short: match.team2Short,
                    name: match.team2Name,
                    score: match.team2Score.isEmpty ? "-" : match.team2Score,
                    tint: rightTint,
                    alignment: .trailing
                )
            }
        }
        .padding(.horizontal, compactMode ? 8 : 10)
        .padding(.vertical, compactMode ? 7 : 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            cardShape
                .fill(Color(red: 0.10, green: 0.115, blue: 0.15).opacity(0.96))
                .overlay(
                    LinearGradient(
                        colors: [
                            leftPalette.primary.opacity(0.22),
                            leftPalette.secondary.opacity(0.10),
                            Color.clear,
                            rightPalette.secondary.opacity(0.10),
                            rightPalette.primary.opacity(0.22),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .overlay(alignment: .leading) {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [leftPalette.primary.opacity(0.22), leftPalette.secondary.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 132, height: 132)
                        .blur(radius: 22)
                        .offset(x: -26, y: -10)
                        .allowsHitTesting(false)
                }
                .overlay(alignment: .trailing) {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [rightPalette.primary.opacity(0.22), rightPalette.secondary.opacity(0.05)],
                                startPoint: .topTrailing,
                                endPoint: .bottomLeading
                            )
                        )
                        .frame(width: 132, height: 132)
                        .blur(radius: 22)
                        .offset(x: 26, y: -10)
                        .allowsHitTesting(false)
                }
                .overlay(
                    cardShape
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.04), Color.black.opacity(0.06)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
        )
        .clipShape(cardShape)
        .overlay(
            cardShape
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.45) : Color.white.opacity(0.06), lineWidth: isSelected ? 1.0 : 0.6)
        )
        .shadow(color: .black.opacity(isSelected ? 0.09 : 0.03), radius: isSelected ? 3 : 1.6, y: 1)
    }

    @ViewBuilder
    private func cricketColumn(short: String, name: String, score: String, tint: Color, alignment: HorizontalAlignment) -> some View {
        let scoreParts = splitCricketScore(score)

        VStack(alignment: alignment, spacing: 2) {
            Text(scoreParts.primary)
                .font(.system(size: compactMode ? 27 : 30, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if let meta = scoreParts.meta {
                Text(meta)
                    .font(.system(size: 10, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundColor(.white.opacity(0.58))
                    .lineLimit(1)
            }
            HStack(spacing: 6) {
                if alignment == .leading {
                    CricketTeamBadge(short: short, teamName: name, tint: tint)
                }
                Text(short.isEmpty ? name : short)
                    .font(.system(size: 11.8, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.88))
                    .lineLimit(1)
                if alignment == .trailing {
                    CricketTeamBadge(short: short, teamName: name, tint: tint)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }

    private func splitCricketScore(_ score: String) -> (primary: String, meta: String?) {
        let trimmed = score.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ("-", nil) }

        guard let open = trimmed.firstIndex(of: "("),
              let close = trimmed[open...].firstIndex(of: ")"),
              open < close
        else {
            return (trimmed, nil)
        }

        let primary = trimmed[..<open].trimmingCharacters(in: .whitespacesAndNewlines)
        let inside = trimmed[trimmed.index(after: open)..<close]
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !inside.isEmpty else {
            return (primary.isEmpty ? trimmed : primary, nil)
        }

        let meta = inside.lowercased().contains("ov") ? inside : "\(inside) ov"
        return (primary.isEmpty ? trimmed : primary, meta)
    }

    private func cricketTeamTint(for name: String, fallback: Color) -> Color {
        cricketTeamPalette(for: name, fallback: (fallback, fallback)).primary
    }

    private func cricketTeamPalette(for name: String, fallback: (primary: Color, secondary: Color)) -> (primary: Color, secondary: Color) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        let normalized = trimmed.lowercased()

        let mapped: [(String, String, String)] = [
            ("india", "#1389d2", "#ff9f2e"), ("australia", "#f1c840", "#0b4ea2"), ("england", "#b82c3a", "#1d3f8f"),
            ("south africa", "#2ea44f", "#f0b429"), ("new zealand", "#334155", "#d74444"), ("pakistan", "#1ea86f", "#e8f5e9"),
            ("sri lanka", "#1f4f9a", "#f1b934"), ("bangladesh", "#2a9d5a", "#d9373e"), ("afghanistan", "#2a6dd8", "#d93b3b"),
            ("west indies", "#7d234a", "#1c4f8a"), ("zimbabwe", "#1f8a47", "#f4bf38"), ("ireland", "#16985c", "#f0943f"),
            ("netherlands", "#dd6f25", "#2f66d8"), ("scotland", "#2f66d8", "#e8edf8"), ("nepal", "#d13a44", "#2f66d8"),
            ("namibia", "#3e64b5", "#dc4c4c"), ("united states", "#2a66b4", "#d54646"), ("usa", "#2a66b4", "#d54646"),
            ("uae", "#239a5d", "#d54646"), ("canada", "#c73636", "#f2f2f2"),
            ("mumbai indians", "#2d5fab", "#d3a754"), ("chennai super kings", "#e2bf2a", "#2d5fab"),
            ("royal challengers", "#b83232", "#1f1f1f"), ("kolkata knight riders", "#6449a8", "#d4b155"),
            ("sunrisers", "#d86b2b", "#1f1f1f"), ("rajasthan royals", "#e053a3", "#2f67c8"),
            ("delhi capitals", "#2f67c8", "#d13a44"), ("punjab kings", "#c43d3d", "#bcc5d6"), ("lucknow super giants", "#46a4d8", "#f4822a"),
            ("gujarat titans", "#3b4f9f", "#23a0d8"),
        ]

        if let palette = mapped.first(where: { normalized.contains($0.0) }) {
            return (Color(hex: palette.1), Color(hex: palette.2))
        }

        let hash = abs(normalized.hashValue % 360)
        let primary = Color(hue: Double(hash) / 360.0, saturation: 0.56, brightness: 0.74)
        let secondary = Color(hue: Double((hash + 28) % 360) / 360.0, saturation: 0.44, brightness: 0.80)
        return (primary, secondary)
    }

    private func cricketHeaderLeading(for match: CricketMatch) -> String {
        if match.isLive {
            if let liveContext = cleanedLiveContext(match) {
                return liveContext
            }
            return "Live"
        }
        if match.isUpcoming { return "Upcoming" }
        return resultLine(for: match)
    }

    private func cricketHeaderTrailing(for match: CricketMatch) -> String {
        let date = Date(timeIntervalSince1970: Double(match.startTimestamp) / 1000.0)
        return DashboardDateFormatters.cardDateTime.string(from: date)
    }

    private func fixtureStageLine(for match: CricketMatch) -> String {
        let value = cleanedFixtureLabel(match.matchDesc)
        if !value.isEmpty { return value }
        if !match.title.isEmpty {
            let titleFixture = cleanedFixtureLabel(match.title)
            if !titleFixture.isEmpty { return titleFixture }
        }
        if match.isLive { return "Live Match" }
        if match.isUpcoming { return "Upcoming" }
        return isTournamentFinal(match) ? "Final" : "Fixture"
    }

    private func resultLine(for match: CricketMatch) -> String {
        if match.isLive { return "Live" }
        if match.isUpcoming { return "Starts Soon" }
        let status = cleanedCompletedStatus(match.status)
        if !status.isEmpty { return status }
        let detail = cleanedCompletedStatus(match.detail)
        if detail.lowercased().contains("won by")
            || detail.lowercased().contains("draw")
            || detail.lowercased().contains("tied")
        {
            return detail
        }
        return "Completed"
    }

    private func cardSubline(for match: CricketMatch) -> String? {
        if match.isLive { return nil }
        if match.isUpcoming { return "Starts Soon" }
        return nil
    }

    private func cleanedCompletedStatus(_ raw: String) -> String {
        var value = raw
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "" }

        value = value
            .replacingOccurrences(
                of: #"^(?i)\s*(result|results|completed|complete)\s*([•:\-]\s*)?"#,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !value.isEmpty else { return "" }

        let lowered = value.lowercased()
        if lowered == "result" || lowered == "results" || lowered == "completed" || lowered == "complete" {
            return ""
        }
        return value
    }

    private func cleanedLiveContext(_ match: CricketMatch) -> String? {
        let candidates = [match.status, match.detail]
        for raw in candidates {
            let value = raw
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            let lowered = value.lowercased()
            if lowered == "live"
                || lowered == "in progress"
                || lowered == "result"
                || lowered.contains("opt to bowl")
                || lowered.contains("opt to bat")
                || lowered.contains("won the toss")
            {
                continue
            }
            return value
        }
        return nil
    }

    private func isTournamentFinal(_ match: CricketMatch) -> Bool {
        let text = "\(match.matchDesc) \(match.title)".lowercased()
        if text.contains("semi-final") || text.contains("quarter-final") || text.contains("super 8") || text.contains("group") {
            return false
        }
        return text.contains(" final") || text.hasPrefix("final")
    }

    private func cleanedFixtureLabel(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "" }
        let lowered = value.lowercased()
        if lowered == "result" || lowered == "results" || lowered == "match" {
            return ""
        }
        if let comma = value.firstIndex(of: ",") {
            let prefix = value[..<comma].trimmingCharacters(in: .whitespacesAndNewlines)
            if !prefix.isEmpty { return prefix }
        }
        return value
    }
}

private struct TeamToken: View {
    let label: String
    let tint: Color

    var body: some View {
        Text(label.isEmpty ? "-" : label)
            .font(.caption2.weight(.medium))
            .foregroundColor(.white.opacity(0.92))
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(tint.opacity(0.46), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.16), lineWidth: 0.6)
            )
            .lineLimit(1)
    }
}

private struct CricketTeamBadge: View {
    let short: String
    let teamName: String
    let logoURL: URL?
    let tint: Color
    private let localAssetBasePath = "/Users/SuhasMBP/Projects/Scorum/MenuScores/BrandAssets"

    init(short: String, teamName: String, logoURL: URL? = nil, tint: Color) {
        self.short = short
        self.teamName = teamName
        self.logoURL = logoURL
        self.tint = tint
    }

    var body: some View {
        if let source = resolvedLogoURL, source.isFileURL, let localImage = MatchaImageCache.image(for: source) {
            Image(nsImage: localImage)
                .resizable()
                .scaledToFill()
                .frame(width: 24, height: 16)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(.white.opacity(0.30), lineWidth: 0.6)
                )
        } else if let source = resolvedLogoURL {
            AsyncImage(url: source) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    TeamToken(label: short, tint: tint)
                }
            }
            .frame(width: 24, height: 16)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(.white.opacity(0.30), lineWidth: 0.6)
            )
        } else if let flag = resolvedFlagURL, flag.isFileURL, let localImage = MatchaImageCache.image(for: flag) {
            Image(nsImage: localImage)
                .resizable()
                .scaledToFill()
                .frame(width: 24, height: 16)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(.white.opacity(0.35), lineWidth: 0.6)
                )
        } else if let flag = resolvedFlagURL {
            AsyncImage(url: flag) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    TeamToken(label: short, tint: tint)
                }
            }
            .frame(width: 24, height: 16)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(.white.opacity(0.35), lineWidth: 0.6)
            )
        } else {
            TeamToken(label: short, tint: tint)
        }
    }

    private var resolvedLogoURL: URL? {
        if let teamLogo = localTeamLogoURL() {
            return teamLogo
        }
        return logoURL
    }

    private var resolvedFlagURL: URL? {
        guard let code = flagCode(for: teamName) else { return nil }
        if let localFlag = localFlagURL(code: code) {
            return localFlag
        }
        return URL(string: "https://flagcdn.com/w80/\(code).png")
    }

    private func localTeamLogoURL() -> URL? {
        guard let key = teamLogoKey(for: teamName, short: short) else { return nil }
        let path = "\(localAssetBasePath)/teams/\(key).png"
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    private func localFlagURL(code: String) -> URL? {
        let path = "\(localAssetBasePath)/flags/\(code).png"
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    private func teamLogoKey(for teamName: String, short: String) -> String? {
        let normalizedShort = short.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedName = teamName.lowercased()
        let knownShorts = Set(["csk", "mi", "kkr", "rcb", "srh", "rr", "dc", "pbks", "lsg", "gt"])
        if knownShorts.contains(normalizedShort) {
            return normalizedShort
        }
        let nameMap: [(String, String)] = [
            ("chennai super kings", "csk"),
            ("mumbai indians", "mi"),
            ("kolkata knight riders", "kkr"),
            ("royal challengers bengaluru", "rcb"),
            ("royal challengers bangalore", "rcb"),
            ("sunrisers hyderabad", "srh"),
            ("rajasthan royals", "rr"),
            ("delhi capitals", "dc"),
            ("punjab kings", "pbks"),
            ("lucknow super giants", "lsg"),
            ("gujarat titans", "gt"),
        ]
        return nameMap.first(where: { normalizedName.contains($0.0) })?.1
    }

    private func flagCode(for team: String) -> String? {
        let normalized = team.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let map: [(String, String)] = [
            ("india", "in"), ("ind", "in"),
            ("australia", "au"), ("aus", "au"),
            ("england", "gb"), ("eng", "gb"),
            ("south africa", "za"), ("rsa", "za"), ("sa", "za"),
            ("new zealand", "nz"), ("nz", "nz"),
            ("pakistan", "pk"), ("pak", "pk"),
            ("sri lanka", "lk"), ("sl", "lk"),
            ("bangladesh", "bd"), ("ban", "bd"), ("bdesh", "bd"),
            ("afghanistan", "af"), ("afg", "af"),
            ("west indies", "jm"), ("wi", "jm"),
            ("ireland", "ie"), ("ire", "ie"),
            ("zimbabwe", "zw"), ("zim", "zw"),
            ("netherlands", "nl"), ("ned", "nl"),
            ("scotland", "gb"), ("sco", "gb"),
            ("nepal", "np"), ("nep", "np"),
            ("namibia", "na"), ("nam", "na"),
            ("united states", "us"), ("usa", "us"),
            ("uae", "ae"), ("canada", "ca"), ("can", "ca"),
            ("chennai super kings", "in"), ("csk", "in"),
            ("mumbai indians", "in"), ("mi", "in"),
            ("kolkata knight riders", "in"), ("kkr", "in"),
            ("royal challengers bengaluru", "in"), ("royal challengers bangalore", "in"), ("rcb", "in"),
            ("sunrisers hyderabad", "in"), ("srh", "in"),
            ("rajasthan royals", "in"), ("rr", "in"),
            ("delhi capitals", "in"), ("dc", "in"),
            ("punjab kings", "in"), ("pbks", "in"),
            ("lucknow super giants", "in"), ("lsg", "in"),
            ("gujarat titans", "in"), ("gt", "in"),
        ]
        if let exact = map.first(where: { $0.0 == normalized })?.1 {
            return exact
        }
        return map.first(where: { normalized.contains($0.0) })?.1
    }
}

private struct SoccerInlineDetailPane: View {
    let item: FavoriteSoccerGame
    let iptvM3UURL: String
    let iptvEPGURL: String
    let enableStreamedProvider: Bool
    let streamedBaseURL: String
    let preloadedWatchOptions: [IPTVResolver.MatchResolution]
    let enableDataFetch: Bool
    let onPin: () -> Void
    let onClose: () -> Void

    @State private var standingsTitle: String = "Standings"
    @State private var standingsRows: [SoccerStandingRow] = []
    @State private var loadingStandings = false
    @State private var smartWatch: IPTVResolver.MatchResolution?
    @State private var smartWatchOptions: [IPTVResolver.MatchResolution] = []
    @State private var selectedSmartWatchKey: String = ""
    @State private var loadingSmartWatch = false
    @State private var selectedTab: SoccerDetailTab = .overview
    @State private var inlineStreamURL: URL?
    @State private var inlineStreamHeaders: [String: String] = [:]
    @State private var inlinePreviewPreferWeb = false
    @State private var didAutoStartLivePreview = false
    @State private var showBroadcastHints = false
    @AppStorage("matchaAppearanceMode") private var appearanceMode = MatchaAppearanceMode.darkFrosted.rawValue

    private var game: Event { item.game }
    private var chromeMode: MatchaAppearanceMode { MatchaChromeStyle.mode(from: appearanceMode) }

    private var channels: [String] {
        guard let broadcasts = game.competitions.first?.broadcasts else { return [] }
        return Array(Set(broadcasts.flatMap { $0.names ?? [] })).sorted()
    }

    private var isLiveOrUpcoming: Bool {
        let state = game.status.type.state.lowercased()
        return state == "in" || state == "pre"
    }

    private var hasAnyWatchProviderConfigured: Bool {
        let hasIPTV = !iptvM3UURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasStreamed = enableStreamedProvider
        return hasIPTV || hasStreamed
    }

    private var selectedSmartWatch: IPTVResolver.MatchResolution? {
        if let matched = smartWatchOptions.first(where: { "\($0.streamURL.absoluteString)|\($0.channelName)" == selectedSmartWatchKey }) {
            return matched
        }
        return smartWatchOptions.first ?? smartWatch
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(item.leagueTitle)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        onClose()
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(MatchaChromeStyle.secondaryForeground(for: chromeMode))
                .buttonStyle(.plain)
            }

            Text(displayText(for: game, league: item.leagueCode))
                .font(.title3.weight(.semibold))
                .foregroundStyle(MatchaChromeStyle.primaryForeground(for: chromeMode))
                .lineLimit(2)

            Text(game.status.type.detail ?? game.status.type.shortDetail ?? "")
                .font(.caption)
                .foregroundColor(MatchaChromeStyle.secondaryForeground(for: chromeMode))
                .lineLimit(2)

            HStack(spacing: 8) {
                Button(action: onPin) {
                    Label("Pin", systemImage: "pin")
                }
                .buttonStyle(MatchaMiniControlButtonStyle())
                if let href = game.links?.first?.href, let url = URL(string: href) {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Label("Center", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(MatchaMiniControlButtonStyle())
                }
                Spacer()
                if loadingStandings {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .font(.caption)
            .controlSize(.small)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .matchaAccessorySurface(corner: 12)

            Picker("Section", selection: $selectedTab) {
                Text("Overview").tag(SoccerDetailTab.overview)
                Text("Broadcast").tag(SoccerDetailTab.broadcast)
                Text("Standings").tag(SoccerDetailTab.standings)
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .labelsHidden()
            .padding(4)
            .matchaAccessorySurface(corner: 12)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 7) {
                    switch selectedTab {
                    case .overview:
                        overviewContent
                    case .broadcast:
                        broadcastContent
                    case .standings:
                        standingsContent
                    }
                }
            }
            .padding(.top, 2)
        }
        .padding(13)
        .matchaGlassContainer()
        .task {
            if enableDataFetch {
                applyPreloadedWatchOptions()
                async let standingsTask: Void = loadStandings()
                async let watchTask: Void = preloadedWatchOptions.isEmpty ? resolveSmartWatch() : noOp()
                _ = await (standingsTask, watchTask)
                maybeAutoStartLivePreviewIfNeeded()
            }
        }
        .task(id: "\(game.id)|\(game.status.type.state)|\(enableDataFetch)") {
            guard enableDataFetch, isLiveOrUpcoming else { return }
            while !Task.isCancelled {
                let refreshNanos: UInt64 = game.status.type.state.lowercased() == "in"
                    ? 30_000_000_000
                    : 90_000_000_000
                try? await Task.sleep(nanoseconds: refreshNanos)
                if Task.isCancelled || !isLiveOrUpcoming { break }
                await resolveSmartWatch()
                maybeAutoStartLivePreviewIfNeeded()
            }
        }
    }

    private var overviewContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            let competition = game.competitions.first
            let teams = competition?.competitors ?? []
            let away = teams.count > 1 ? teams[1] : nil
            let home = teams.count > 0 ? teams[0] : nil

            whereToWatchOverviewCard

            if !soccerOverviewInfoRows.isEmpty {
                detailInfoCard(rows: soccerOverviewInfoRows)
            }

            if let key = keyMatchNote, !key.isEmpty {
                Text(key)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .matchaSubtleCard()
            }

            soccerTeamRow(team: away?.team, score: away?.score)
            soccerTeamRow(team: home?.team, score: home?.score)
        }
    }

    @ViewBuilder
    private var whereToWatchOverviewCard: some View {
        if isLiveOrUpcoming {
            VStack(alignment: .leading, spacing: 6) {
                MatchaSectionHeading(title: "Where to Watch")

                if loadingSmartWatch {
                    ProgressView("Finding stream…")
                        .font(.caption2)
                } else if let smartWatch = selectedSmartWatch {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(smartWatch.channelName)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                MatchaProviderBadge(source: smartWatch.matchedBy)
                            }
                            if let program = smartWatch.programTitle, !program.isEmpty {
                                Text(program)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        Spacer()
                        HStack(spacing: 6) {
                            Button {
                                inlineStreamURL = smartWatch.streamURL
                                inlineStreamHeaders = smartWatch.requestHeaders
                                inlinePreviewPreferWeb = smartWatch.matchedBy == "streamed"
                            } label: {
                                Image(systemName: "play.fill")
                                    .frame(width: 24, height: 20)
                            }
                            .buttonStyle(MatchaMiniControlButtonStyle(prominent: true))
                            .help("Preview")
                            Button {
                                NSWorkspace.shared.open(smartWatch.streamURL)
                            } label: {
                                Image(systemName: "arrow.up.right")
                                    .frame(width: 24, height: 20)
                            }
                            .buttonStyle(MatchaMiniControlButtonStyle())
                            .help("Open")
                            Button {
                                openDetachedStream(smartWatch, pinnedToCorner: false)
                            } label: {
                                Image(systemName: "pip")
                                    .frame(width: 24, height: 20)
                            }
                            .buttonStyle(MatchaMiniControlButtonStyle())
                            .help("PiP")
                            Button {
                                openDetachedStream(smartWatch, pinnedToCorner: true)
                            } label: {
                                Image(systemName: "pin.fill")
                                    .frame(width: 24, height: 20)
                            }
                            .buttonStyle(MatchaMiniControlButtonStyle())
                            .help("Pin to corner")
                        }
                        .controlSize(.small)
                    }
                    .matchaSectionCard(fillOpacity: 0.48)
                    if smartWatchOptions.count > 1 {
                        Picker("Stream", selection: $selectedSmartWatchKey) {
                            ForEach(Array(smartWatchOptions.enumerated()), id: \.offset) { _, option in
                                Text("\(option.channelName) • \(option.matchedBy == "streamed" ? "Streamed" : "IPTV")")
                                    .tag("\(option.streamURL.absoluteString)|\(option.channelName)")
                            }
                        }
                        .pickerStyle(.menu)
                        .font(.caption2)
                    }
                } else if !hasAnyWatchProviderConfigured {
                    Text("Add a stream provider in Settings to surface channels here.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    Text("No stream match right now.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var broadcastContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !isLiveOrUpcoming {
                Text("Streams appear here for live and upcoming fixtures.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                if loadingSmartWatch {
                    ProgressView("Finding stream…")
                        .font(.caption2)
                } else if let smartWatch = selectedSmartWatch {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(smartWatch.channelName)
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(1)
                                    MatchaProviderBadge(source: smartWatch.matchedBy)
                                }
                                if let program = smartWatch.programTitle, !program.isEmpty {
                                    Text(program)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            Spacer()
                            HStack(spacing: 6) {
                                Button {
                                    inlineStreamURL = smartWatch.streamURL
                                    inlineStreamHeaders = smartWatch.requestHeaders
                                    inlinePreviewPreferWeb = smartWatch.matchedBy == "streamed"
                                } label: {
                                    Image(systemName: "play.fill")
                                        .frame(width: 24, height: 20)
                                }
                                .buttonStyle(MatchaMiniControlButtonStyle(prominent: true))
                                .help("Preview")

                                Button {
                                    NSWorkspace.shared.open(smartWatch.streamURL)
                                } label: {
                                    Image(systemName: "arrow.up.right")
                                        .frame(width: 24, height: 20)
                                }
                                .buttonStyle(MatchaMiniControlButtonStyle())
                                .help("Open")
                            }
                            .controlSize(.small)
                        }
                        .matchaSectionCard(fillOpacity: 0.48)
                        if smartWatchOptions.count > 1 {
                            Picker("Stream", selection: $selectedSmartWatchKey) {
                                ForEach(Array(smartWatchOptions.enumerated()), id: \.offset) { _, option in
                                    Text("\(option.channelName) • \(option.matchedBy == "streamed" ? "Streamed" : "IPTV")")
                                        .tag("\(option.streamURL.absoluteString)|\(option.channelName)")
                                }
                            }
                            .pickerStyle(.menu)
                            .font(.caption2)
                        }
                    }
                } else if !hasAnyWatchProviderConfigured {
                    Text("Add a stream provider in Settings to surface channels here.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    Text("No stream match right now.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                if !channels.isEmpty {
                    DisclosureGroup(isExpanded: $showBroadcastHints) {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(channels.prefix(4)), id: \.self) { channel in
                                HStack {
                                    Text(channel)
                                        .font(.caption2)
                                    Spacer()
                                    if !iptvM3UURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        Button("Preview") {
                                            Task {
                                                if let stream = await IPTVResolver.shared.resolveStream(
                                                    channelNames: [channel],
                                                    m3uURLString: iptvM3UURL
                                                ) {
                                                    inlineStreamURL = stream.streamURL
                                                    inlineStreamHeaders = stream.requestHeaders
                                                    inlinePreviewPreferWeb = false
                                                }
                                            }
                                        }
                                        .font(.caption2)
                                        .buttonStyle(.bordered)
                                    }
                                }
                                .padding(.vertical, 1)
                            }
                        }
                    } label: {
                        Text("Broadcast hints (\(channels.count))")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("No broadcast hints from the fixture feed.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            if let inlineStreamURL {
                InlineMutedStreamPlayer(streamURL: inlineStreamURL, requestHeaders: inlineStreamHeaders, preferWebPreview: inlinePreviewPreferWeb) {
                    self.inlineStreamURL = nil
                    self.inlineStreamHeaders = [:]
                    self.inlinePreviewPreferWeb = false
                }
            }
        }
    }

    private func resolveSmartWatch() async {
        guard isLiveOrUpcoming else {
            smartWatch = nil
            smartWatchOptions = []
            selectedSmartWatchKey = ""
            return
        }
        let m3u = iptvM3UURL.trimmingCharacters(in: .whitespacesAndNewlines)

        loadingSmartWatch = true
        defer { loadingSmartWatch = false }

        let competitors = game.competitions.first?.competitors ?? []
        let away = competitors.count > 1 ? competitors[1].team : nil
        let home = competitors.count > 0 ? competitors[0].team : nil
        let matchDate = DashboardDateFormatters.isoWithFractional.date(from: game.date)
            ?? DashboardDateFormatters.iso.date(from: game.date)
            ?? Date()

        let query = IPTVResolver.MatchQuery(
            sport: "soccer",
            league: item.leagueTitle,
            homeTeam: home?.displayName ?? home?.name ?? "Home",
            awayTeam: away?.displayName ?? away?.name ?? "Away",
            startDate: matchDate,
            isLive: game.status.type.state.lowercased() == "in",
            isUpcoming: game.status.type.state.lowercased() == "pre",
            broadcastHints: channels
        )

        var merged: [IPTVResolver.MatchResolution] = []
        if enableStreamedProvider {
            let streamedMatches = await StreamedResolver.resolveMatchStreams(
                query: query,
                config: .init(enabled: true, baseURLString: streamedBaseURL),
                limit: 6
            )
            merged.append(contentsOf: streamedMatches)
        }
        if !m3u.isEmpty {
            let iptvMatches = await IPTVResolver.shared.resolveMatchStreams(
                query: query,
                m3uURLString: m3u,
                epgURLString: effectiveEPGURL,
                limit: 6
            )
            merged.append(contentsOf: iptvMatches)
        }
        let matches = dedupeMatchOptions(merged, limit: 8)
        smartWatchOptions = matches
        if let preserved = matches.first(where: { "\($0.streamURL.absoluteString)|\($0.channelName)" == selectedSmartWatchKey }) {
            smartWatch = preserved
        } else {
            smartWatch = matches.first
            selectedSmartWatchKey = matches.first.map { "\($0.streamURL.absoluteString)|\($0.channelName)" } ?? ""
        }
    }

    private func applyPreloadedWatchOptions() {
        guard !preloadedWatchOptions.isEmpty else { return }
        smartWatchOptions = preloadedWatchOptions
        if let preserved = preloadedWatchOptions.first(where: { "\($0.streamURL.absoluteString)|\($0.channelName)" == selectedSmartWatchKey }) {
            smartWatch = preserved
        } else {
            smartWatch = preloadedWatchOptions.first
            selectedSmartWatchKey = preloadedWatchOptions.first.map { "\($0.streamURL.absoluteString)|\($0.channelName)" } ?? ""
        }
    }

    private func maybeAutoStartLivePreviewIfNeeded() {
        guard game.status.type.state.lowercased() == "in", !didAutoStartLivePreview else { return }
        guard let preferred = preferredLiveAutoStartOption(from: smartWatchOptions) else { return }

        selectedSmartWatchKey = "\(preferred.streamURL.absoluteString)|\(preferred.channelName)"
        inlineStreamURL = preferred.streamURL
        inlineStreamHeaders = preferred.requestHeaders
        inlinePreviewPreferWeb = preferred.matchedBy == "streamed"
        didAutoStartLivePreview = true
    }

    private func preferredLiveAutoStartOption(from options: [IPTVResolver.MatchResolution]) -> IPTVResolver.MatchResolution? {
        let streamed = options.filter { $0.matchedBy == "streamed" }
        if let sourceOne = streamed.first(where: { option in
            option.channelName.localizedCaseInsensitiveContains("#1")
                || option.channelName.localizedCaseInsensitiveContains("stream 1")
        }) {
            return sourceOne
        }
        return streamed.first ?? options.first
    }

    private func openDetachedStream(_ option: IPTVResolver.MatchResolution, pinnedToCorner: Bool) {
        StreamPreviewWindowManager.shared.open(
            title: option.channelName,
            streamURL: option.streamURL,
            requestHeaders: option.requestHeaders,
            preferWebPreview: option.matchedBy == "streamed",
            pinnedToCorner: pinnedToCorner
        )
    }

    private func noOp() async {}

    private func dedupeMatchOptions(_ options: [IPTVResolver.MatchResolution], limit: Int) -> [IPTVResolver.MatchResolution] {
        var seen: Set<String> = []
        var out: [IPTVResolver.MatchResolution] = []
        for option in options {
            let key = "\(option.streamURL.absoluteString)|\(option.channelName)"
            if seen.contains(key) { continue }
            seen.insert(key)
            out.append(option)
            if out.count >= limit { break }
        }
        return out
    }

    private var effectiveEPGURL: String? {
        let epg = iptvEPGURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !epg.isEmpty { return epg }

        let m3u = iptvM3UURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !m3u.isEmpty else { return nil }
        if m3u.contains("/m3u") {
            return m3u.replacingOccurrences(of: "/m3u", with: "/epg")
        }
        if m3u.lowercased().hasSuffix(".m3u") {
            return String(m3u.dropLast(4)) + "/epg"
        }
        return nil
    }

    private var standingsContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(standingsTitle)
                .font(.caption)
                .foregroundColor(.secondary)

            if loadingStandings {
                ProgressView()
            } else if standingsRows.isEmpty {
                Text("Standings unavailable for this competition.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: 3) {
                    HStack(spacing: 8) {
                        Text("#")
                            .frame(width: 20, alignment: .leading)
                        Text("Team")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Record")
                            .frame(width: 64, alignment: .trailing)
                        Text("Pts")
                            .frame(width: 30, alignment: .trailing)
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.secondary)

                    ForEach(standingsRows) { row in
                        HStack(spacing: 8) {
                            Text(row.rank)
                                .frame(width: 20, alignment: .leading)
                            Text(row.teamName)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(row.record)
                                .frame(width: 64, alignment: .trailing)
                            Text(row.points)
                                .frame(width: 30, alignment: .trailing)
                        }
                        .font(.caption.monospacedDigit())
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white.opacity(0.018))
                        )
                    }
                }
                .matchaSectionCard()
            }
        }
    }

    private var soccerOverviewInfoRows: [(String, String)] {
        let competition = game.competitions.first
        var rows: [(String, String)] = [("Kickoff", cardDateTime(fromISO: game.date))]

        if let status = cleanedSoccerStatusSummary(),
           !status.isEmpty {
            rows.append((isLiveOrUpcoming ? "Status" : "Result", status))
        }

        if let venue = competition?.venue?.fullName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !venue.isEmpty,
           venue.lowercased() != "unknown" {
            rows.append(("Venue", venue))
        }

        if let weather = weatherLine {
            rows.append(("Weather", weather))
        }

        if rows.count > 4 {
            return Array(rows.prefix(4))
        }
        return rows
    }

    private func cleanedSoccerStatusSummary() -> String? {
        let raw = (game.status.type.detail ?? game.status.type.shortDetail ?? "")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }

        let cleaned = raw
            .replacingOccurrences(of: #"^(?i)\s*(result|results|ft|full time)\s*([•:\-]\s*)?"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.isEmpty || cleaned == "—" || cleaned == "-" {
            return nil
        }
        return cleaned
    }

    @ViewBuilder
    private func soccerTeamRow(team: Team?, score: String?) -> some View {
        HStack(spacing: 8) {
            TeamLogo(urlString: team?.logo, fallback: team?.abbreviation ?? "?")
            Text(team?.displayName ?? team?.name ?? "Team")
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text((score?.isEmpty == false) ? (score ?? "-") : "-")
                .font(.caption.monospacedDigit())
        }
        .matchaSectionCard()
    }

    private func loadStandings() async {
        loadingStandings = true
        defer { loadingStandings = false }

        guard let standings = await SoccerStandingsService.shared.topStandings(for: item.leagueCode, maxRows: 12) else {
            standingsRows = []
            standingsTitle = "Standings"
            return
        }

        standingsTitle = standings.title
        standingsRows = standings.rows
    }

    private var weatherLine: String? {
        if let desc = game.weather?.displayValue, !desc.isEmpty {
            if let temp = game.weather?.temperature {
                return "\(temp)° • \(desc)"
            }
            return desc
        }
        return nil
    }

    private var keyMatchNote: String? {
        let comp = game.competitions.first
        if let headline = comp?.headlines?.first?.description, !headline.isEmpty {
            return headline
        }
        if let note = comp?.notes?.first?.headline, !note.isEmpty {
            return note
        }
        if let text = game.competitions.first?.situation?.lastPlay?.text, !text.isEmpty {
            return text
        }
        return nil
    }

    private func cardDateTime(fromISO iso: String) -> String {
        let date = DashboardDateFormatters.isoWithFractional.date(from: iso) ?? DashboardDateFormatters.iso.date(from: iso)
        guard let date else { return formattedDate(from: iso) + " • " + formattedTime(from: iso) }
        return DashboardDateFormatters.cardDateTime.string(from: date)
    }

    @ViewBuilder
    private func detailInfoCard(rows: [(String, String)]) -> some View {
        VStack(spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.0)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(width: 58, alignment: .leading)
                    Text(row.1)
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(2)
                }
            }
        }
        .matchaSectionCard()
    }
}

private struct CricketInlineDetailPane: View {
    let match: CricketMatch
    let iptvM3UURL: String
    let iptvEPGURL: String
    let enableStreamedProvider: Bool
    let streamedBaseURL: String
    let preloadedWatchOptions: [IPTVResolver.MatchResolution]
    let enableDataFetch: Bool
    let onPin: (String) -> Void
    let onClose: () -> Void

    @State private var scorecardSummary: CricketScorecardSummary?
    @State private var loadingScorecard = false
    @State private var expandedInnings: Set<Int> = []
    @State private var selectedInningsNumber: Int?
    @State private var standingsTable: CricketStandingsTable?
    @State private var selectedStandingsGroupID: String = ""
    @State private var loadingStandings = false
    @State private var smartWatch: IPTVResolver.MatchResolution?
    @State private var smartWatchOptions: [IPTVResolver.MatchResolution] = []
    @State private var selectedSmartWatchKey: String = ""
    @State private var loadingSmartWatch = false
    @State private var selectedTab: CricketDetailTab = .overview
    @State private var resolvedPointsTableURL: URL?
    @State private var inlineStreamURL: URL?
    @State private var inlineStreamHeaders: [String: String] = [:]
    @State private var inlinePreviewPreferWeb = false
    @State private var didAutoStartLivePreview = false
    @AppStorage("matchaAppearanceMode") private var appearanceMode = MatchaAppearanceMode.darkFrosted.rawValue
    private static let allStandingsGroupsID = "__all_groups__"
    private var chromeMode: MatchaAppearanceMode { MatchaChromeStyle.mode(from: appearanceMode) }

    private var allStandingsGroup: CricketStandingGroup? {
        guard let groups = standingsTable?.groups, !groups.isEmpty else { return nil }
        let mergedRows = groups.flatMap(\.rows)
        guard !mergedRows.isEmpty else { return nil }
        let normalizedRows = mergedRows.enumerated().map { index, row in
            CricketStandingRow(
                id: "all-\(row.id)-\(index)",
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
        return CricketStandingGroup(
            id: Self.allStandingsGroupsID,
            name: "All Groups",
            rows: normalizedRows
        )
    }

    private var standingsPickerGroups: [CricketStandingGroup] {
        guard let groups = standingsTable?.groups, !groups.isEmpty else { return [] }
        if groups.count > 1, let allStandingsGroup {
            return [allStandingsGroup] + groups
        }
        return groups
    }

    private var selectedStandingsGroup: CricketStandingGroup? {
        if !selectedStandingsGroupID.isEmpty {
            if selectedStandingsGroupID == Self.allStandingsGroupsID {
                return allStandingsGroup
            }
            return standingsTable?.groups.first(where: { $0.id == selectedStandingsGroupID })
        }
        return standingsPickerGroups.first
    }

    private var isLiveOrUpcoming: Bool {
        match.isLive || match.isUpcoming || (isFutureOrStartingSoon && !isFinalizedMatch)
    }

    private var isFutureOrStartingSoon: Bool {
        let start = Date(timeIntervalSince1970: Double(match.startTimestamp) / 1000.0)
        // Keep a small grace window for fixtures that just started but feed state lags.
        return start > Date().addingTimeInterval(-20 * 60)
    }

    private var isFinalizedMatch: Bool {
        let text = "\(match.state) \(match.status)".lowercased()
        return text.contains("complete")
            || text.contains("completed")
            || text.contains("result")
            || text.contains("won by")
            || text.contains("draw")
            || text.contains("abandon")
            || text.contains("cancel")
    }

    private var hasAnyWatchProviderConfigured: Bool {
        let hasIPTV = !iptvM3UURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasStreamed = enableStreamedProvider
        return hasIPTV || hasStreamed
    }

    private var selectedSmartWatch: IPTVResolver.MatchResolution? {
        if let matched = smartWatchOptions.first(where: { "\($0.streamURL.absoluteString)|\($0.channelName)" == selectedSmartWatchKey }) {
            return matched
        }
        return smartWatchOptions.first ?? smartWatch
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(match.seriesName.isEmpty ? "Cricket" : match.seriesName)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        onClose()
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(MatchaChromeStyle.secondaryForeground(for: chromeMode))
                .buttonStyle(.plain)
            }

            HStack(spacing: 6) {
                let statusSummary = cleanedOverviewResult(match.status)
                if !match.matchDesc.isEmpty {
                    Text(cleanedOverviewFixture(match.matchDesc))
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(MatchaChromeStyle.secondaryForeground(for: chromeMode))
                        .lineLimit(1)
                }
                if !statusSummary.isEmpty {
                    Text("•")
                        .font(.caption2)
                        .foregroundColor(MatchaChromeStyle.tertiaryForeground(for: chromeMode))
                    Text(statusSummary)
                        .font(.caption2)
                        .foregroundColor(MatchaChromeStyle.secondaryForeground(for: chromeMode))
                        .lineLimit(1)
                }
                Spacer()
                Text(matchDayLine)
                    .font(.caption2)
                    .foregroundColor(MatchaChromeStyle.secondaryForeground(for: chromeMode))
            }

            HStack(spacing: 8) {
                Button {
                    onPin(compactPinnedTitle())
                } label: {
                    Label("Pin", systemImage: "pin")
                }
                .buttonStyle(MatchaMiniControlButtonStyle())

                Button {
                    NSWorkspace.shared.open(match.url)
                } label: {
                    Label("Open Center", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(MatchaMiniControlButtonStyle())

                Spacer()
                if loadingScorecard || loadingStandings {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .font(.caption2)
            .controlSize(.small)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .matchaAccessorySurface(corner: 12)

            Picker("Section", selection: $selectedTab) {
                Text("Overview").tag(CricketDetailTab.overview)
                Text("Scorecard").tag(CricketDetailTab.scorecard)
                Text("Standings").tag(CricketDetailTab.standings)
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .labelsHidden()
            .padding(4)
            .matchaAccessorySurface(corner: 12)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 7) {
                    switch selectedTab {
                    case .overview:
                        overviewContent
                    case .scorecard:
                        scorecardContent
                    case .standings:
                        standingsContent
                    }
                }
            }
            .padding(.top, 2)
        }
        .padding(13)
        .matchaGlassContainer()
        .task(id: match.id) {
            if enableDataFetch {
                applyPreloadedWatchOptions()
                if preloadedWatchOptions.isEmpty {
                    await resolveSmartWatch()
                }
                maybeAutoStartLivePreviewIfNeeded()
                if match.isUpcoming {
                    scorecardSummary = nil
                    standingsTable = nil
                    selectedStandingsGroupID = ""
                    resolvedPointsTableURL = nil
                    loadingScorecard = false
                    loadingStandings = false
                    return
                }
                await loadScorecardSummary()
            }
        }
        .task(id: "\(match.id)|\(match.state)|\(match.status)|\(enableDataFetch)") {
            guard enableDataFetch, (match.isLive || match.isUpcoming) else { return }
            while !Task.isCancelled {
                let refreshNanos: UInt64 = match.isLive ? 30_000_000_000 : 120_000_000_000
                try? await Task.sleep(nanoseconds: refreshNanos)
                if Task.isCancelled || (!match.isLive && !match.isUpcoming) { break }
                await resolveSmartWatch()
                maybeAutoStartLivePreviewIfNeeded()
                if match.isLive, !loadingScorecard {
                    await loadScorecardSummary()
                }
            }
        }
    }

    private var overviewContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            whereToWatchCard
            overviewScoreSummaryCard
            overviewTopHighlightsBlock

            if !overviewInfoRows.isEmpty {
                detailInfoCard(rows: overviewInfoRows)
            }

            if let standingsGroup = selectedStandingsGroup, !standingsGroup.rows.isEmpty {
                Divider()
                MatchaSectionHeading(title: "Standings Snapshot")

                VStack(spacing: 4) {
                    ForEach(Array(standingsGroup.rows.prefix(4)), id: \.id) { row in
                        HStack(spacing: 8) {
                            Text("\(row.rank)")
                                .font(.caption2.monospacedDigit())
                                .foregroundColor(.secondary)
                                .frame(width: 16, alignment: .leading)
                            CricketTeamBadge(
                                short: shortName(for: row),
                                teamName: row.teamName,
                                logoURL: row.teamLogoURL,
                                tint: Color(nsColor: .systemBlue)
                            )
                            Text(row.teamName)
                                .font(.caption2)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("\(row.points) pts")
                                .font(.caption2.monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(8)
                .matchaSectionCard(corner: 10, fillOpacity: 0.34, strokeOpacity: 0.08)
            }

            if !match.isUpcoming {
                VStack(alignment: .leading, spacing: 5) {
                    MatchaSectionHeading(title: "Quick Totals")
                    if !match.team1Innings.isEmpty || !match.team2Innings.isEmpty {
                        quickInningsLine(title: match.team1Short, innings: match.team1Innings)
                        quickInningsLine(title: match.team2Short, innings: match.team2Innings)
                    } else {
                        Text("Innings totals will appear once feed data is available.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Text("Open the Scorecard tab for full batter, bowler, and fall-of-wickets details.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                }
            }
        }
    }

    @ViewBuilder
    private var whereToWatchCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            MatchaSectionHeading(title: "Where to Watch")

            if !isLiveOrUpcoming {
                Text("Streams appear here for live and upcoming fixtures.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else if loadingSmartWatch {
                ProgressView("Finding stream…")
                    .font(.caption2)
            } else if let smartWatch = selectedSmartWatch {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(smartWatch.channelName)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            MatchaProviderBadge(source: smartWatch.matchedBy)
                        }
                        if let program = smartWatch.programTitle, !program.isEmpty {
                            Text(program)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }
                    Spacer()
                    HStack(spacing: 6) {
                        Button {
                            inlineStreamURL = smartWatch.streamURL
                            inlineStreamHeaders = smartWatch.requestHeaders
                            inlinePreviewPreferWeb = smartWatch.matchedBy == "streamed"
                        } label: {
                            Image(systemName: "play.fill")
                                .frame(width: 24, height: 20)
                        }
                        .buttonStyle(MatchaMiniControlButtonStyle(prominent: true))
                        .help("Preview")
                        Button {
                            NSWorkspace.shared.open(smartWatch.streamURL)
                        } label: {
                            Image(systemName: "arrow.up.right")
                                .frame(width: 24, height: 20)
                        }
                        .buttonStyle(MatchaMiniControlButtonStyle())
                        .help("Open")
                        Button {
                            openDetachedStream(smartWatch, pinnedToCorner: false)
                        } label: {
                            Image(systemName: "pip")
                                .frame(width: 24, height: 20)
                        }
                        .buttonStyle(MatchaMiniControlButtonStyle())
                        .help("PiP")
                        Button {
                            openDetachedStream(smartWatch, pinnedToCorner: true)
                        } label: {
                            Image(systemName: "pin.fill")
                                .frame(width: 24, height: 20)
                        }
                        .buttonStyle(MatchaMiniControlButtonStyle())
                        .help("Pin to corner")
                    }
                    .controlSize(.small)
                }
                .matchaSectionCard(fillOpacity: 0.48)
                if smartWatchOptions.count > 1 {
                    Picker("Stream", selection: $selectedSmartWatchKey) {
                        ForEach(Array(smartWatchOptions.enumerated()), id: \.offset) { _, option in
                            Text("\(option.channelName) • \(option.matchedBy == "streamed" ? "Streamed" : "IPTV")")
                                .tag("\(option.streamURL.absoluteString)|\(option.channelName)")
                        }
                    }
                    .pickerStyle(.menu)
                    .font(.caption2)
                }
            } else {
                Group {
                    if !hasAnyWatchProviderConfigured {
                        Text("Add a stream provider in Settings to surface channels here.")
                    } else {
                        Text("No stream match right now.")
                    }
                }
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if let inlineStreamURL {
                InlineMutedStreamPlayer(streamURL: inlineStreamURL, requestHeaders: inlineStreamHeaders, preferWebPreview: inlinePreviewPreferWeb) {
                    self.inlineStreamURL = nil
                    self.inlineStreamHeaders = [:]
                    self.inlinePreviewPreferWeb = false
                }
            }
        }
    }

    @ViewBuilder
    private var overviewTopHighlightsBlock: some View {
        if let summary = scorecardSummary, !summary.innings.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if let player = playerHighlightValue
                {
                    HStack(spacing: 8) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color(red: 0.39, green: 0.77, blue: 0.52))
                        Text(playerHighlightTitle)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(player)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .matchaSectionCard(corner: 9, fillOpacity: 0.40, strokeOpacity: 0.10)
                }

                ForEach(summary.innings.prefix(2)) { innings in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 7) {
                            CricketTeamBadge(
                                short: innings.battingTeamShort,
                                teamName: innings.battingTeamShort,
                                tint: Color(nsColor: .systemBlue)
                            )
                            Text(innings.totalLine)
                                .font(.system(size: 12.5, weight: .semibold, design: .rounded).monospacedDigit())
                                .foregroundColor(.primary)
                            Spacer()
                        }

                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Top Batters")
                                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                                    .foregroundColor(.secondary)
                                ForEach(Array(innings.batters.prefix(3))) { batter in
                                    highlightStatLine(
                                        left: batter.name,
                                        right: "\(batter.runs) (\(batter.balls))"
                                    )
                                }
                                if innings.batters.isEmpty {
                                    Text("No batter stats")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            VStack(alignment: .leading, spacing: 5) {
                                Text("Top Bowlers")
                                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                                    .foregroundColor(.secondary)
                                ForEach(Array(innings.bowlers.prefix(3))) { bowler in
                                    highlightStatLine(
                                        left: bowler.name,
                                        right: "\(bowler.wickets)/\(bowler.runs) (\(oversText(bowler.overs)))"
                                    )
                                }
                                if innings.bowlers.isEmpty {
                                    Text("No bowler stats")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .matchaSectionCard()
                }
            }
        }
    }

    private var overviewScoreSummaryCard: some View {
        let team1 = splitOverviewScore(match.team1Score)
        let team2 = splitOverviewScore(match.team2Score)
        let fixture = cleanedOverviewFixture(match.matchDesc)
        let result = cleanedOverviewResult(match.status)

        return VStack(alignment: .leading, spacing: 9) {
            Text("\(match.seriesName.isEmpty ? "Cricket" : match.seriesName) • \(matchDayLine)")
                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
                .lineLimit(1)

            HStack(alignment: .top, spacing: 10) {
                overviewTeamScoreColumn(
                    teamName: match.team1Name,
                    teamShort: match.team1Short,
                    score: team1.primary,
                    meta: team1.meta,
                    alignment: .leading
                )

                VStack(spacing: 4) {
                    Text(overviewCenterPrimaryLine(fixture: fixture))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)

                    Text(overviewCenterSecondaryLine(result: result))
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 2)

                overviewTeamScoreColumn(
                    teamName: match.team2Name,
                    teamShort: match.team2Short,
                    score: team2.primary,
                    meta: team2.meta,
                    alignment: .trailing
                )
            }
        }
        .matchaSectionCard(corner: 12, fillOpacity: 0.58, strokeOpacity: 0.10)
    }

    private func overviewCenterPrimaryLine(fixture: String) -> String {
        if !fixture.isEmpty { return fixture }
        if match.isLive { return "Live Match" }
        if match.isUpcoming { return "Upcoming" }
        return "Match"
    }

    private func overviewCenterSecondaryLine(result: String) -> String {
        if !result.isEmpty { return result }
        if match.isLive {
            let liveSummary = cleanedOverviewResult(match.status)
            if !liveSummary.isEmpty {
                return liveSummary
            }
        }
        if match.isUpcoming { return "Starts Soon" }
        return matchDayLine
    }

    @ViewBuilder
    private func overviewTeamScoreColumn(
        teamName: String,
        teamShort: String,
        score: String,
        meta: String?,
        alignment: HorizontalAlignment
    ) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            CricketTeamBadge(short: teamShort, teamName: teamName, tint: Color(nsColor: .systemBlue))
            Text(score)
                .font(.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if let meta, !meta.isEmpty {
                Text("(\(meta))")
                    .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Text(teamName)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }

    private func splitOverviewScore(_ score: String) -> (primary: String, meta: String?) {
        let trimmed = score.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ("-", nil) }

        guard let open = trimmed.firstIndex(of: "("),
              let close = trimmed[open...].firstIndex(of: ")"),
              open < close
        else {
            return (trimmed, nil)
        }

        let primary = trimmed[..<open].trimmingCharacters(in: .whitespacesAndNewlines)
        let inside = trimmed[trimmed.index(after: open)..<close]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "ov", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return (primary.isEmpty ? trimmed : primary, inside.isEmpty ? nil : inside)
    }

    private func cleanedOverviewFixture(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "" }

        if let comma = value.firstIndex(of: ",") {
            let firstPart = value[..<comma].trimmingCharacters(in: .whitespacesAndNewlines)
            if !firstPart.isEmpty { return firstPart }
        }
        return value
    }

    private func cleanedOverviewResult(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "Result", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var matchDayLine: String {
        let date = Date(timeIntervalSince1970: Double(match.startTimestamp) / 1000.0)
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        if cal.isDateInTomorrow(date) { return "Tomorrow" }
        return DashboardDateFormatters.cardDateTime.string(from: date)
    }

    private var playerHighlightTitle: String {
        if let raw = scorecardSummary?.playerOfMatch?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty
        {
            return "Player of the Match"
        }
        return "Top Performer"
    }

    private var playerHighlightValue: String? {
        if let raw = scorecardSummary?.playerOfMatch?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty
        {
            return raw
        }
        return inferredTopPerformer
    }

    private var inferredTopPerformer: String? {
        guard let summary = scorecardSummary, !summary.innings.isEmpty else { return nil }

        let allBatters = summary.innings.flatMap(\.batters)
        if let bestBatter = allBatters.max(by: { lhs, rhs in
            if lhs.runs == rhs.runs { return lhs.strikeRate < rhs.strikeRate }
            return lhs.runs < rhs.runs
        }),
           bestBatter.runs > 0
        {
            return "\(bestBatter.name) • \(bestBatter.runs) (\(bestBatter.balls))"
        }

        let allBowlers = summary.innings.flatMap(\.bowlers)
        if let bestBowler = allBowlers.max(by: { lhs, rhs in
            if lhs.wickets == rhs.wickets { return lhs.runs > rhs.runs }
            return lhs.wickets < rhs.wickets
        }),
           bestBowler.wickets > 0
        {
            return "\(bestBowler.name) • \(bestBowler.wickets)/\(bestBowler.runs) (\(oversText(bestBowler.overs)))"
        }

        return nil
    }

    @ViewBuilder
    private func highlightStatLine(left: String, right: String) -> some View {
        HStack(spacing: 8) {
            Text(left)
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(right)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }

    private func oversText(_ overs: Double) -> String {
        if overs.rounded(.towardZero) == overs {
            return "\(Int(overs))"
        }
        return String(format: "%.1f", overs)
    }

    private var scorecardContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            MatchaSectionHeading(title: "Scorecard")

            if match.isUpcoming {
                Text("Detailed scorecard will appear once the match starts.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else if let scorecardSummary, !scorecardSummary.innings.isEmpty {
                let inningsList = scorecardSummary.innings
                let selected = selectedInningsNumber ?? inningsList.first?.inningsNumber

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(inningsList) { innings in
                            Button {
                                selectedInningsNumber = innings.inningsNumber
                            } label: {
                                Text("\(innings.battingTeamShort) • Inn \(innings.inningsNumber)")
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule()
                                            .fill(selected == innings.inningsNumber ? Color.accentColor.opacity(0.18) : Color.white.opacity(0.05))
                                    )
                                    .overlay(
                                        Capsule()
                                            .stroke(selected == innings.inningsNumber ? Color.accentColor.opacity(0.50) : Color.white.opacity(0.07), lineWidth: 0.7)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 1)
                }

                if let chosen = inningsList.first(where: { $0.inningsNumber == selected }) {
                    inningsPerformanceCard(chosen)
                }
            } else {
                Text("Live scorecard rows are loading. If unavailable, pull-to-refresh in the main menu.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var standingsContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                MatchaSectionHeading(title: "Series Standings")
                Spacer()
                if loadingStandings {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if match.isUpcoming {
                Text("Standings will load when this fixture has active series data.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else if standingsPickerGroups.count > 1 {
                Picker("Group", selection: $selectedStandingsGroupID) {
                    ForEach(standingsPickerGroups) { group in
                        Text(group.name).tag(group.id)
                    }
                }
                .pickerStyle(.menu)
            }

            if let standingsGroup = selectedStandingsGroup, !standingsGroup.rows.isEmpty {
                standingsTableCard(for: standingsGroup)
            } else {
                Text("Standings unavailable for this series.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private func standingsTableCard(for standingsGroup: CricketStandingGroup) -> some View {
        Text(standingsGroup.name)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundColor(.secondary)

        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Text("#").frame(width: 16, alignment: .leading)
                Text("Team").frame(maxWidth: .infinity, alignment: .leading)
                Text("P").frame(width: 18, alignment: .trailing)
                Text("W").frame(width: 18, alignment: .trailing)
                Text("L").frame(width: 18, alignment: .trailing)
                Text("PTS").frame(width: 28, alignment: .trailing)
                Text("NRR").frame(width: 44, alignment: .trailing)
            }
            .font(.caption2.weight(.semibold))
            .foregroundColor(.secondary)
            .padding(.bottom, 2)

            ForEach(Array(standingsGroup.rows.enumerated()), id: \.element.id) { index, row in
                standingsRow(row, index: index)
            }
        }
        .matchaSectionCard()
    }

    @ViewBuilder
    private func standingsRow(_ row: CricketStandingRow, index: Int) -> some View {
        HStack(spacing: 8) {
            Text("\(row.rank)").frame(width: 16, alignment: .leading)
            CricketTeamBadge(
                short: shortName(for: row),
                teamName: row.teamName,
                logoURL: row.teamLogoURL,
                tint: Color(nsColor: .systemBlue)
            )
            Text(row.teamName)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
            Text("\(row.played)").frame(width: 18, alignment: .trailing)
            Text("\(row.won)").frame(width: 18, alignment: .trailing)
            Text("\(row.lost)").frame(width: 18, alignment: .trailing)
            Text("\(row.points)").frame(width: 28, alignment: .trailing)
            Text(row.nrr).frame(width: 44, alignment: .trailing)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .font(.caption2.monospacedDigit())
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(index.isMultiple(of: 2) ? Color.white.opacity(0.016) : Color.clear)
        )
    }

    @ViewBuilder
    private func detailTeamRow(name: String, short: String, score: String) -> some View {
        HStack {
            CricketTeamBadge(short: short, teamName: name, tint: Color(nsColor: .systemBlue))
            Text(name)
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(score.isEmpty ? "-" : score)
                .font(.caption.monospacedDigit())
        }
    }

    @ViewBuilder
    private func inningsCard(title: String, innings: [CricketInning]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))

            if innings.isEmpty {
                Text("No innings data yet")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                ForEach(innings, id: \.number) { inning in
                    HStack {
                        Text("Inn \(inning.number)")
                            .frame(width: 44, alignment: .leading)
                            .foregroundColor(.secondary)
                        Text(inning.line)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.caption.monospacedDigit())
                }
            }
        }
        .matchaSectionCard(corner: 9, fillOpacity: 0.46, strokeOpacity: 0.08)
    }

    @ViewBuilder
    private func inningsPerformanceCard(_ innings: CricketInningsBreakdown) -> some View {
        let isExpanded = expandedInnings.contains(innings.inningsNumber)
        let displayedBatters = isExpanded ? innings.batters : Array(innings.batters.prefix(6))
        let displayedBowlers = isExpanded ? innings.bowlers : Array(innings.bowlers.prefix(5))

        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Innings \(innings.inningsNumber)")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(innings.totalLine)
                    .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundColor(.secondary)
            }

            Text("Batting")
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)

            if displayedBatters.isEmpty {
                Text("No batter breakdown available.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: 3) {
                    HStack(spacing: 8) {
                        Text("Batter").frame(maxWidth: .infinity, alignment: .leading)
                        Text("R").frame(width: 26, alignment: .trailing)
                        Text("B").frame(width: 26, alignment: .trailing)
                        Text("4s").frame(width: 26, alignment: .trailing)
                        Text("6s").frame(width: 26, alignment: .trailing)
                        Text("S/R").frame(width: 52, alignment: .trailing)
                    }
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)

                    ForEach(displayedBatters) { batter in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 8) {
                                Text(batter.name)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .lineLimit(1)
                                Text("\(batter.runs)")
                                    .frame(width: 26, alignment: .trailing)
                                Text("\(batter.balls)")
                                    .frame(width: 26, alignment: .trailing)
                                Text("\(batter.fours)")
                                    .frame(width: 26, alignment: .trailing)
                                Text("\(batter.sixes)")
                                    .frame(width: 26, alignment: .trailing)
                                Text(String(format: "%.2f", batter.strikeRate))
                                    .frame(width: 52, alignment: .trailing)
                            }
                            if !batter.outDescription.isEmpty {
                                Text(batter.outDescription)
                                    .font(.system(size: 10.5, weight: .regular))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .font(.system(size: 11.5, weight: .regular, design: .rounded).monospacedDigit())
                        .padding(.vertical, 2)
                    }
                }
            }

            if !isExpanded && innings.batters.count > displayedBatters.count {
                Text("+\(innings.batters.count - displayedBatters.count) more batters")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }

            Divider().opacity(0.2)
            HStack {
                Text("Extras")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text(innings.extras.line)
                    .font(.system(size: 11, weight: .regular, design: .rounded).monospacedDigit())
                    .foregroundColor(.secondary)
            }
            HStack {
                Text("Total runs")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text("\(innings.totalRuns)/\(innings.wickets) (\(String(format: "%.1f", innings.overs)) ov)")
                    .font(.system(size: 11, weight: .regular, design: .rounded).monospacedDigit())
                    .foregroundColor(.secondary)
            }
            if !innings.powerplaySummary.isEmpty {
                HStack(alignment: .top) {
                    Text("Powerplay")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text(innings.powerplaySummary)
                        .font(.system(size: 10, weight: .regular, design: .rounded).monospacedDigit())
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }

            Divider().opacity(0.2)
            Text("Bowling")
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)

            if displayedBowlers.isEmpty {
                Text("No bowler breakdown available.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: 3) {
                    HStack(spacing: 8) {
                        Text("Bowler").frame(maxWidth: .infinity, alignment: .leading)
                        Text("O").frame(width: 42, alignment: .trailing)
                        Text("M").frame(width: 24, alignment: .trailing)
                        Text("R").frame(width: 24, alignment: .trailing)
                        Text("W").frame(width: 24, alignment: .trailing)
                        Text("Econ").frame(width: 44, alignment: .trailing)
                    }
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)

                    ForEach(displayedBowlers) { bowler in
                        HStack(spacing: 8) {
                            Text(bowler.name)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lineLimit(1)
                            Text("\(String(format: "%.1f", bowler.overs)) ov")
                                .frame(width: 42, alignment: .trailing)
                            Text("\(bowler.maidens)")
                                .frame(width: 24, alignment: .trailing)
                            Text("\(bowler.runs)")
                                .frame(width: 24, alignment: .trailing)
                            Text("\(bowler.wickets)")
                                .frame(width: 24, alignment: .trailing)
                            Text(String(format: "%.2f", bowler.economy))
                                .frame(width: 44, alignment: .trailing)
                        }
                        .font(.system(size: 11.5, weight: .regular, design: .rounded).monospacedDigit())
                        .padding(.vertical, 2)
                    }
                }
            }

            if !isExpanded && innings.bowlers.count > displayedBowlers.count {
                Text("+\(innings.bowlers.count - displayedBowlers.count) more bowlers")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }

            if isExpanded && !innings.fallOfWickets.isEmpty {
                Divider()
                Text("Fall of wickets")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text((isExpanded ? innings.fallOfWickets : Array(innings.fallOfWickets.prefix(8))).joined(separator: " • "))
                    .font(.system(size: 10, weight: .regular, design: .rounded).monospacedDigit())
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isExpanded && !innings.yetToBat.isEmpty {
                Divider()
                Text("Yet to bat")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(innings.yetToBat.joined(separator: ", "))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Button(isExpanded ? "Show Less" : "Show More") {
                if isExpanded {
                    expandedInnings.remove(innings.inningsNumber)
                } else {
                    expandedInnings.insert(innings.inningsNumber)
                }
            }
            .font(.caption2)
            .buttonStyle(.borderless)
        }
        .matchaSectionCard(corner: 9, fillOpacity: 0.46, strokeOpacity: 0.08)
    }

    private func loadScorecardSummary() async {
        if match.isUpcoming {
            scorecardSummary = nil
            standingsTable = nil
            selectedStandingsGroupID = ""
            resolvedPointsTableURL = nil
            loadingScorecard = false
            loadingStandings = false
            return
        }

        loadingScorecard = true
        loadingStandings = true
        defer { loadingScorecard = false }
        defer { loadingStandings = false }
        scorecardSummary = await CricketFeed.fetchScorecardSummary(matchID: match.id)
        selectedInningsNumber = scorecardSummary?.innings.first?.inningsNumber
        standingsTable = nil
        selectedStandingsGroupID = ""
        resolvedPointsTableURL = nil

        var pointsURL = scorecardSummary?.pointsTableURL
        if pointsURL == nil {
            pointsURL = await CricketFeed.fetchPointsTableURL(matchID: match.id)
        }
        resolvedPointsTableURL = pointsURL

        guard let pointsURL,
              let standings = await CricketFeed.fetchStandings(from: pointsURL)
        else {
            return
        }

        let teamShorts = [match.team1Short.uppercased(), match.team2Short.uppercased()]
        standingsTable = standings

        let preferredGroup = standings.groups.first(where: { group in
            let names = group.rows.map { $0.teamName.uppercased() }
            return teamShorts.allSatisfy { short in names.contains(where: { $0.contains(short) }) }
        }) ?? standings.groups.first

        if standings.groups.count > 1 {
            selectedStandingsGroupID = Self.allStandingsGroupsID
        } else {
            selectedStandingsGroupID = preferredGroup?.id ?? ""
        }
    }

    private func resolveSmartWatch() async {
        guard isLiveOrUpcoming else {
            smartWatch = nil
            smartWatchOptions = []
            selectedSmartWatchKey = ""
            return
        }

        let m3u = iptvM3UURL.trimmingCharacters(in: .whitespacesAndNewlines)

        loadingSmartWatch = true
        defer { loadingSmartWatch = false }

        let query = IPTVResolver.MatchQuery(
            sport: "cricket",
            league: match.seriesName,
            homeTeam: match.team1Name,
            awayTeam: match.team2Name,
            startDate: Date(timeIntervalSince1970: Double(match.startTimestamp) / 1000.0),
            isLive: match.isLive,
            isUpcoming: match.isUpcoming,
            broadcastHints: []
        )

        var merged: [IPTVResolver.MatchResolution] = []
        if enableStreamedProvider {
            let streamedMatches = await StreamedResolver.resolveMatchStreams(
                query: query,
                config: .init(enabled: true, baseURLString: streamedBaseURL),
                limit: 6
            )
            merged.append(contentsOf: streamedMatches)
        }
        if !m3u.isEmpty {
            let iptvMatches = await IPTVResolver.shared.resolveMatchStreams(
                query: query,
                m3uURLString: m3u,
                epgURLString: iptvEPGURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? nil
                    : iptvEPGURL,
                limit: 6
            )
            merged.append(contentsOf: iptvMatches)
        }
        let matches = dedupeMatchOptions(merged, limit: 8)
        smartWatchOptions = matches
        if let preserved = matches.first(where: { "\($0.streamURL.absoluteString)|\($0.channelName)" == selectedSmartWatchKey }) {
            smartWatch = preserved
        } else {
            smartWatch = matches.first
            selectedSmartWatchKey = matches.first.map { "\($0.streamURL.absoluteString)|\($0.channelName)" } ?? ""
        }
    }

    private func applyPreloadedWatchOptions() {
        guard !preloadedWatchOptions.isEmpty else { return }
        smartWatchOptions = preloadedWatchOptions
        if let preserved = preloadedWatchOptions.first(where: { "\($0.streamURL.absoluteString)|\($0.channelName)" == selectedSmartWatchKey }) {
            smartWatch = preserved
        } else {
            smartWatch = preloadedWatchOptions.first
            selectedSmartWatchKey = preloadedWatchOptions.first.map { "\($0.streamURL.absoluteString)|\($0.channelName)" } ?? ""
        }
    }

    private func maybeAutoStartLivePreviewIfNeeded() {
        guard match.isLive, !didAutoStartLivePreview else { return }
        guard let preferred = preferredLiveAutoStartOption(from: smartWatchOptions) else { return }

        selectedSmartWatchKey = "\(preferred.streamURL.absoluteString)|\(preferred.channelName)"
        inlineStreamURL = preferred.streamURL
        inlineStreamHeaders = preferred.requestHeaders
        inlinePreviewPreferWeb = preferred.matchedBy == "streamed"
        didAutoStartLivePreview = true
    }

    private func preferredLiveAutoStartOption(from options: [IPTVResolver.MatchResolution]) -> IPTVResolver.MatchResolution? {
        let streamed = options.filter { $0.matchedBy == "streamed" }
        if let sourceOne = streamed.first(where: { option in
            option.channelName.localizedCaseInsensitiveContains("#1")
                || option.channelName.localizedCaseInsensitiveContains("stream 1")
        }) {
            return sourceOne
        }
        return streamed.first ?? options.first
    }

    private func compactPinnedTitle() -> String {
        if match.isLive {
            var parts: [String] = [match.scoreLine]
            if let ticker = liveTickerLine(), !ticker.isEmpty {
                parts.append(ticker)
            } else if let context = match.conciseLiveContext {
                parts.append(context)
            }
            return parts.joined(separator: " • ")
        }

        if match.isUpcoming {
            let fixture = cleanedOverviewFixture(match.matchDesc)
            if fixture.isEmpty {
                return "\(match.team1Short) vs \(match.team2Short)"
            }
            return "\(match.team1Short) vs \(match.team2Short) • \(fixture)"
        }

        let result = cleanedOverviewResult(match.status)
        if result.isEmpty {
            return match.scoreLine
        }
        return "\(match.scoreLine) • \(result)"
    }

    private func liveTickerLine() -> String? {
        guard let innings = scorecardSummary?.innings.last else { return nil }
        let activeBatters = innings.batters.filter { batter in
            let out = batter.outDescription.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return out.isEmpty || out.contains("not out")
        }
        let keyBatter = activeBatters.max(by: { $0.runs < $1.runs }) ?? innings.batters.max(by: { $0.runs < $1.runs })
        let lastPartnership = innings.partnerships.last

        var bits: [String] = []
        if let keyBatter {
            bits.append("Bat: \(shortPlayerName(keyBatter.name)) \(keyBatter.runs)(\(keyBatter.balls))")
        }
        if let lastPartnership, lastPartnership.runs > 0 {
            bits.append("Part: \(lastPartnership.runs)(\(lastPartnership.balls))")
        }
        return bits.isEmpty ? nil : bits.joined(separator: " • ")
    }

    private func shortPlayerName(_ name: String) -> String {
        let parts = name.split(separator: " ")
        guard let last = parts.last else { return name }
        return String(last)
    }

    private func openDetachedStream(_ option: IPTVResolver.MatchResolution, pinnedToCorner: Bool) {
        StreamPreviewWindowManager.shared.open(
            title: option.channelName,
            streamURL: option.streamURL,
            requestHeaders: option.requestHeaders,
            preferWebPreview: option.matchedBy == "streamed",
            pinnedToCorner: pinnedToCorner
        )
    }

    private func dedupeMatchOptions(_ options: [IPTVResolver.MatchResolution], limit: Int) -> [IPTVResolver.MatchResolution] {
        var seen: Set<String> = []
        var out: [IPTVResolver.MatchResolution] = []
        for option in options {
            let key = "\(option.streamURL.absoluteString)|\(option.channelName)"
            if seen.contains(key) { continue }
            seen.insert(key)
            out.append(option)
            if out.count >= limit { break }
        }
        return out
    }

    private func cardDateTime(fromUnixMs value: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(value) / 1000.0)
        return DashboardDateFormatters.cardDateTime.string(from: date)
    }

    private var overviewInfoRows: [(String, String)] {
        var rows: [(String, String)] = []

        let result = cleanedOverviewResult(match.status)
        if !result.isEmpty {
            rows.append(("Result", result))
        }

        rows.append(("Start", cardDateTime(fromUnixMs: match.startTimestamp)))

        if let toss = normalizedInfoValue(scorecardSummary?.toss) {
            rows.append(("Toss", toss))
        }
        if let venue = normalizedInfoValue(scorecardSummary?.venue) {
            rows.append(("Venue", venue))
        }

        let fixture = cleanedOverviewFixture(match.matchDesc)
        if !fixture.isEmpty {
            rows.append(("Fixture", fixture))
        }

        if let potm = normalizedInfoValue(playerHighlightValue) {
            rows.append(("POTM", potm))
        }

        if rows.count > 5 {
            return Array(rows.prefix(5))
        }
        return rows
    }

    private func normalizedInfoValue(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "-" { return nil }
        return trimmed
    }

    private func shortName(for row: CricketStandingRow) -> String {
        if let short = row.teamShort?.trimmingCharacters(in: .whitespacesAndNewlines),
           !short.isEmpty {
            return short
        }
        return row.teamName.prefix(3).uppercased()
    }

    @ViewBuilder
    private func detailInfoCard(rows: [(String, String)]) -> some View {
        VStack(spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.0)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(width: 58, alignment: .leading)
                    Text(row.1)
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(2)
                }
            }
        }
        .matchaSectionCard(corner: 10, fillOpacity: 0.54, strokeOpacity: 0.10)
    }

    @ViewBuilder
    private func quickInningsLine(title: String, innings: [String]) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)
                .frame(width: 42, alignment: .leading)
            Text(innings.joined(separator: " • "))
                .font(.caption.monospacedDigit())
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
        }
        .matchaSectionCard()
    }
}

@MainActor
private final class StreamPreviewWindowManager {
    static let shared = StreamPreviewWindowManager()
    private var pinnedWindow: NSWindow?
    private var popoutWindow: NSWindow?

    func open(
        title: String,
        streamURL: URL,
        requestHeaders: [String: String],
        preferWebPreview: Bool,
        pinnedToCorner: Bool
    ) {
        let target = pinnedToCorner ? pinnedWindow : popoutWindow
        if let target {
            target.contentViewController = NSHostingController(
                rootView: DetachedStreamWindowContent(
                    title: title,
                    streamURL: streamURL,
                    requestHeaders: requestHeaders,
                    preferWebPreview: preferWebPreview,
                    onClose: { target.close() }
                )
            )
            if pinnedToCorner { placeInTopRightCorner(window: target) }
            target.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(contentViewController: NSViewController())
        let chromeBackground = NSColor(
            calibratedRed: 0.05,
            green: 0.06,
            blue: 0.09,
            alpha: pinnedToCorner ? 0.92 : 0.88
        )
        window.title = pinnedToCorner ? "Matcha PiP" : "Matcha Stream"
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces]
        window.styleMask = pinnedToCorner ? [.borderless, .resizable, .fullSizeContentView] : [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.setContentSize(NSSize(width: pinnedToCorner ? 440 : 760, height: pinnedToCorner ? 290 : 480))
        window.minSize = NSSize(width: pinnedToCorner ? 340 : 520, height: pinnedToCorner ? 220 : 320)
        window.level = pinnedToCorner ? .floating : .normal
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = chromeBackground
        window.hasShadow = true
        window.isMovableByWindowBackground = !pinnedToCorner
        if let contentView = window.contentView {
            contentView.wantsLayer = true
            contentView.layerContentsRedrawPolicy = .duringViewResize
            contentView.layer?.masksToBounds = true
            contentView.layer?.cornerRadius = pinnedToCorner ? 16 : 14
            contentView.layer?.cornerCurve = .continuous
            contentView.layer?.backgroundColor = chromeBackground.cgColor
        }

        if pinnedToCorner {
            placeInTopRightCorner(window: window)
            pinnedWindow = window
        } else {
            popoutWindow = window
            window.center()
        }

        window.contentViewController = NSHostingController(
            rootView: DetachedStreamWindowContent(
                title: title,
                streamURL: streamURL,
                requestHeaders: requestHeaders,
                preferWebPreview: preferWebPreview,
                onClose: { window.close() }
            )
        )

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.pinnedWindow === window { self.pinnedWindow = nil }
                if self.popoutWindow === window { self.popoutWindow = nil }
            }
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func placeInTopRightCorner(window: NSWindow) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let size = window.frame.size
        let x = visible.maxX - size.width - 14
        let y = visible.maxY - size.height - 20
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

private struct DetachedStreamWindowContent: View {
    let title: String
    let streamURL: URL
    let requestHeaders: [String: String]
    let preferWebPreview: Bool
    let onClose: () -> Void

    var body: some View {
        InlineMutedStreamPlayer(
            streamURL: streamURL,
            requestHeaders: requestHeaders,
            preferWebPreview: preferWebPreview,
            presentation: .detached
        ) { onClose() }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }
}

private enum StreamPlayerPresentation {
    case embedded
    case detached
}

private struct InlineMutedStreamPlayer: View {
    let streamURL: URL
    let requestHeaders: [String: String]
    let preferWebPreview: Bool
    let presentation: StreamPlayerPresentation
    let onClose: () -> Void

    @State private var player: AVPlayer?
    @State private var statusObserver: NSKeyValueObservation?
    @State private var itemFailureObserver: NSObjectProtocol?
    @State private var playbackError: String?
    @State private var previewTask: Task<Void, Never>?
    @State private var webPreviewURL: URL?
    @State private var activePreviewURL: URL?
    @State private var didAttemptFFmpegFallback = false
    @State private var ffmpegProcess: Process?
    @State private var ffmpegOutputDirectory: URL?

    init(
        streamURL: URL,
        requestHeaders: [String: String],
        preferWebPreview: Bool,
        presentation: StreamPlayerPresentation = .embedded,
        onClose: @escaping () -> Void
    ) {
        self.streamURL = streamURL
        self.requestHeaders = requestHeaders
        self.preferWebPreview = preferWebPreview
        self.presentation = presentation
        self.onClose = onClose
    }

    private var isDetached: Bool {
        presentation == .detached
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            previewSurface

            HStack(spacing: 6) {
                Button {
                    NSWorkspace.shared.open(streamURL)
                } label: {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 22, height: 20)
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.black.opacity(0.26))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.6)
                )

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 22, height: 20)
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.black.opacity(0.26))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.6)
                )
            }
            .padding(6)
        }
        .background(playerChromeBackground)
        .onAppear {
            if player == nil {
                startPreviewIfPossible()
            }
        }
        .onDisappear {
            teardownPlayer()
        }
    }

    @ViewBuilder
    private var previewSurface: some View {
        if playbackError != nil {
            VStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white.opacity(0.78))
            }
            .frame(maxWidth: .infinity, maxHeight: isDetached ? .infinity : nil)
            .frame(height: isDetached ? nil : 170)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.24))
            )
        } else if let webPreviewURL {
            NativeWebPreview(url: webPreviewURL, requestHeaders: requestHeaders)
                .frame(maxWidth: .infinity, maxHeight: isDetached ? .infinity : nil)
                .frame(height: isDetached ? nil : 180)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else if let player {
            NativeAVPlayerView(player: player)
                .frame(maxWidth: .infinity, maxHeight: isDetached ? .infinity : nil)
                .frame(height: isDetached ? nil : 170)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: isDetached ? .infinity : nil)
                .frame(height: isDetached ? nil : 170)
        }
    }

    @ViewBuilder
    private var playerChromeBackground: some View {
        if isDetached {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.82))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.7)
                )
        } else {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(red: 0.10, green: 0.12, blue: 0.17).opacity(0.78))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.7)
                )
        }
    }

    private func startPreviewIfPossible() {
        guard let scheme = streamURL.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            playbackError = "Only HTTP/HTTPS streams can be previewed inline."
            return
        }
        playbackError = nil
        previewTask?.cancel()
        previewTask = Task {
            let resolvedURL = await resolvePreviewURL(from: streamURL)
            if Task.isCancelled { return }
            await MainActor.run {
                activePreviewURL = resolvedURL
                if shouldUseWebPreview(for: resolvedURL) {
                    configureWebPreview(with: resolvedURL)
                } else {
                    configureAndPlay(with: resolvedURL)
                }
            }
        }
    }

    private func teardownPlayer() {
        previewTask?.cancel()
        previewTask = nil
        player?.pause()
        player = nil
        webPreviewURL = nil
        activePreviewURL = nil
        didAttemptFFmpegFallback = false
        ffmpegProcess?.terminate()
        ffmpegProcess = nil
        if let ffmpegOutputDirectory {
            try? FileManager.default.removeItem(at: ffmpegOutputDirectory)
            self.ffmpegOutputDirectory = nil
        }
        statusObserver = nil
        if let itemFailureObserver {
            NotificationCenter.default.removeObserver(itemFailureObserver)
            self.itemFailureObserver = nil
        }
    }

    private func configureWebPreview(with resolvedURL: URL) {
        player?.pause()
        player = nil
        playbackError = nil
        webPreviewURL = resolvedURL
    }

    private func configureAndPlay(with resolvedURL: URL) {
        webPreviewURL = nil
        var assetOptions: [String: Any] = [:]
        if !requestHeaders.isEmpty {
            assetOptions["AVURLAssetHTTPHeaderFieldsKey"] = requestHeaders
            if let userAgent = requestHeaders.first(where: { $0.key.caseInsensitiveCompare("User-Agent") == .orderedSame })?.value,
               !userAgent.isEmpty {
                assetOptions["AVURLAssetHTTPUserAgentKey"] = userAgent
            }
        }
        let asset = AVURLAsset(url: resolvedURL, options: assetOptions)
        let item = AVPlayerItem(asset: asset)
        let p = AVPlayer(playerItem: item)
        p.isMuted = true
        player = p
        playbackError = nil

        statusObserver = item.observe(\.status, options: [.new, .initial]) { _, _ in
            DispatchQueue.main.async {
                if item.status == .failed {
                    if let activePreviewURL {
                        attemptFFmpegFallbackOrWeb(for: activePreviewURL)
                    } else {
                        playbackError = item.error?.localizedDescription ?? "The stream format is not playable in this view."
                        p.pause()
                    }
                }
            }
        }

        itemFailureObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            if let activePreviewURL {
                attemptFFmpegFallbackOrWeb(for: activePreviewURL)
            } else {
                playbackError = item.error?.localizedDescription ?? "Failed to play the stream."
                p.pause()
            }
        }

        p.play()
    }

    private func shouldUseWebPreview(for url: URL) -> Bool {
        if preferWebPreview { return true }
        let ext = url.pathExtension.lowercased()
        let directMediaExtensions: Set<String> = ["m3u8", "m3u", "mpd", "mp4", "mov", "ts", "webm"]
        if directMediaExtensions.contains(ext) {
            return false
        }
        let host = (url.host ?? "").lowercased()
        return host.contains("streamed.")
    }

    private func attemptFFmpegFallbackOrWeb(for url: URL) {
        guard !didAttemptFFmpegFallback else {
            configureWebPreview(with: url)
            return
        }
        didAttemptFFmpegFallback = true
        Task {
            if let localHLS = await transcodeToLocalHLS(from: url) {
                await MainActor.run {
                    activePreviewURL = localHLS
                    configureAndPlay(with: localHLS)
                }
            } else {
                await MainActor.run {
                    configureWebPreview(with: url)
                }
            }
        }
    }

    private func transcodeToLocalHLS(from inputURL: URL) async -> URL? {
        guard let ffmpegPath = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
            .first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            return nil
        }

        let outputDir = FileManager.default.temporaryDirectory.appendingPathComponent("matcha-preview-\(UUID().uuidString)")
        let outputIndex = outputDir.appendingPathComponent("index.m3u8")
        do {
            try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)

        var arguments: [String] = [
            "-hide_banner", "-loglevel", "error",
            "-fflags", "nobuffer",
            "-rw_timeout", "10000000"
        ]

        if !requestHeaders.isEmpty {
            let headerBlob = requestHeaders.map { "\($0.key): \($0.value)" }.joined(separator: "\r\n") + "\r\n"
            arguments += ["-headers", headerBlob]
        }

        arguments += [
            "-i", inputURL.absoluteString,
            "-map", "0:v:0?", "-map", "0:a:0?",
            "-c:v", "copy",
            "-c:a", "aac", "-b:a", "128k",
            "-f", "hls",
            "-hls_time", "2",
            "-hls_list_size", "6",
            "-hls_flags", "delete_segments+append_list+omit_endlist",
            "-hls_segment_filename", outputDir.appendingPathComponent("seg_%05d.ts").path,
            outputIndex.path
        ]
        process.arguments = arguments

        do {
            try process.run()
        } catch {
            try? FileManager.default.removeItem(at: outputDir)
            return nil
        }

        await MainActor.run {
            ffmpegProcess?.terminate()
            ffmpegProcess = process
            ffmpegOutputDirectory = outputDir
        }

        for _ in 0 ..< 30 {
            if Task.isCancelled { return nil }
            if FileManager.default.fileExists(atPath: outputIndex.path),
               let attrs = try? FileManager.default.attributesOfItem(atPath: outputIndex.path),
               let size = attrs[.size] as? NSNumber,
               size.intValue > 0 {
                return outputIndex
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }

        process.terminate()
        try? FileManager.default.removeItem(at: outputDir)
        await MainActor.run {
            if ffmpegProcess === process {
                ffmpegProcess = nil
                ffmpegOutputDirectory = nil
            }
        }
        return nil
    }

    private func resolvePreviewURL(from sourceURL: URL) async -> URL {
        let ext = sourceURL.pathExtension.lowercased()
        let mustResolvePlaylist = ext == "m3u" || ext == "m3u8"
        if mustResolvePlaylist == false { return sourceURL }

        var request = URLRequest(url: sourceURL)
        request.timeoutInterval = 8
        request.setValue("Matcha/2.2", forHTTPHeaderField: "User-Agent")
        for (key, value) in requestHeaders where !value.isEmpty {
            request.setValue(value, forHTTPHeaderField: key)
        }

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let text = String(data: data, encoding: .utf8) else {
            return sourceURL
        }

        // Keep HLS playlists intact for AVPlayer (master/media playlist).
        if text.contains("#EXTM3U"), text.contains("#EXT-X-") {
            return sourceURL
        }

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if let direct = URL(string: line),
               let scheme = direct.scheme?.lowercased(),
               scheme == "http" || scheme == "https" {
                return direct
            }
            if let relative = URL(string: line, relativeTo: sourceURL)?.absoluteURL,
               let scheme = relative.scheme?.lowercased(),
               scheme == "http" || scheme == "https" {
                return relative
            }
        }

        return sourceURL
    }
}

private struct NativeWebPreview: NSViewRepresentable {
    let url: URL
    let requestHeaders: [String: String]

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsBackForwardNavigationGestures = false
        webView.autoresizingMask = [.width, .height]
        var request = URLRequest(url: url)
        for (key, value) in requestHeaders where !value.isEmpty {
            request.setValue(value, forHTTPHeaderField: key)
        }
        webView.load(request)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        guard nsView.url?.absoluteString != url.absoluteString else { return }
        var request = URLRequest(url: url)
        for (key, value) in requestHeaders where !value.isEmpty {
            request.setValue(value, forHTTPHeaderField: key)
        }
        nsView.load(request)
    }
}

private struct NativeAVPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.showsSharingServiceButton = false
        view.autoresizingMask = [.width, .height]
        view.videoGravity = .resizeAspect
        view.player = player
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
    }
}

private extension Color {
    init?(hex: String?) {
        guard let hex else { return nil }

        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard cleaned.count == 6, let value = Int(cleaned, radix: 16) else { return nil }

        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0

        self.init(red: red, green: green, blue: blue)
    }
}
