import SwiftUI

private enum OnboardingStep: Int, CaseIterable {
    case welcome
    case favorites
    case watch

    var title: String {
        switch self {
        case .welcome: return "Welcome"
        case .favorites: return "Favorites"
        case .watch: return "Watch"
        }
    }

    var subtitle: String {
        switch self {
        case .welcome:
            return "Set Matcha up once, then it stays out of the way."
        case .favorites:
            return "Pick the teams and competitions you actually care about."
        case .watch:
            return "Optionally connect IPTV to unlock smarter channel matching."
        }
    }
}

private enum OnboardingSearchKindFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case team = "Teams"
    case competition = "Competitions"
    case country = "Countries"

    var id: String { rawValue }
}

private enum OnboardingSearchSportFilter: String, CaseIterable, Identifiable {
    case all = "All Sports"
    case soccer = "Soccer"
    case cricket = "Cricket"

    var id: String { rawValue }
}

struct MatchaOnboardingView: View {
    let openPreferencesAction: () -> Void

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("iptvM3UURL") private var iptvM3UURL = ""
    @AppStorage("iptvEPGURL") private var iptvEPGURL = ""
    @AppStorage("enableStreamedProvider") private var enableStreamedProvider = true
    @AppStorage(FavoriteSelectionsStore.storageKey) private var favoriteSelectionsJSON = ""

    @State private var step: OnboardingStep = .welcome
    @State private var query = ""
    @State private var kindFilter: OnboardingSearchKindFilter = .all
    @State private var sportFilter: OnboardingSearchSportFilter = .all
    @State private var soccerTeamCatalog: [FavoriteCatalogItem] = []
    @State private var isLoadingSoccerTeams = false
    @State private var loadedSoccerTeams = false

    private var selected: [FavoriteSelection] {
        FavoriteSelectionsStore.decode(from: favoriteSelectionsJSON)
    }

    private var selectedTeams: [FavoriteSelection] {
        selected.filter { $0.kind == .team }
    }

    private var selectedCompetitions: [FavoriteSelection] {
        selected.filter { $0.kind == .competition }
    }

    private var hasFavorites: Bool {
        !selected.isEmpty
    }

    private var totalSelectedCount: Int {
        selected.count
    }

    private var hasM3U: Bool {
        !iptvM3UURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasEPG: Bool {
        !iptvEPGURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var catalog: [FavoriteCatalogItem] {
        FavoriteCatalogProvider.dedupe(FavoriteCatalogProvider.allStaticItems() + soccerTeamCatalog)
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
                return item.country?.lowercased().contains(q) ?? false
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

    private var visibleCatalogItems: [FavoriteCatalogItem] {
        Array(filteredCatalog.prefix(24))
    }

    private var selectionSummaryText: String {
        if totalSelectedCount == 0 {
            return "Nothing selected yet"
        }

        var parts: [String] = []
        if !selectedTeams.isEmpty {
            parts.append("\(selectedTeams.count) team\(selectedTeams.count == 1 ? "" : "s")")
        }
        if !selectedCompetitions.isEmpty {
            parts.append("\(selectedCompetitions.count) competition\(selectedCompetitions.count == 1 ? "" : "s")")
        }
        return parts.joined(separator: " • ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeader

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    switch step {
                    case .welcome:
                        welcomeStep
                    case .favorites:
                        favoritesStep
                    case .watch:
                        watchStep
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.top, 2)
            }

            footer
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
        )
        .task {
            if !enableStreamedProvider {
                enableStreamedProvider = true
            }
            await loadSoccerTeamCatalogIfNeeded()
        }
    }

    private var stepHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        ForEach(OnboardingStep.allCases, id: \.rawValue) { item in
                            Capsule(style: .continuous)
                                .fill(item.rawValue <= step.rawValue ? Color.accentColor : Color.white.opacity(0.12))
                                .frame(width: item == step ? 38 : 22, height: 6)
                                .animation(.easeInOut(duration: 0.18), value: step.rawValue)
                        }
                    }

                    Text(step.title)
                        .font(.system(size: 24, weight: .bold))

                    Text(step.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                Text("Step \(step.rawValue + 1) of \(OnboardingStep.allCases.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
            }
        }
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image("TahoeIcon")
                        .resizable()
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Matcha keeps scores close and quiet.")
                            .font(.headline)
                        Text("Follow your teams, watch live updates in the menu bar, and only open detail when it matters.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                onboardingBullet(
                    icon: "star.circle.fill",
                    title: "Pick favorites",
                    detail: "Choose teams or competitions so the menu stays focused."
                )
                onboardingBullet(
                    icon: "sportscourt.fill",
                    title: "Track live and upcoming",
                    detail: "Matcha starts with current and next fixtures instead of burying you in old scores."
                )
                onboardingBullet(
                    icon: "play.tv.fill",
                    title: "Add watch sources later if you want",
                    detail: "Streamed works by default. IPTV M3U + EPG unlock smarter channel matching."
                )
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
            )

            HStack(spacing: 8) {
                onboardingMetricPill(title: "Sports", value: "Cricket + Soccer")
                onboardingMetricPill(title: "Watch", value: "Streamed ready")
            }

            HStack(spacing: 8) {
                quickStartChip(item: FavoriteCatalogProvider.quickStartPicks[0])
                quickStartChip(item: FavoriteCatalogProvider.quickStartPicks[4])
                quickStartChip(item: FavoriteCatalogProvider.quickStartPicks[2])
            }
        }
    }

    private var favoritesStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            favoritesQuickPicksSection
            Divider()
            favoritesSearchControls
            favoritesSelectedSection
            favoritesResultsSection
        }
    }

    private var favoritesQuickPicksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Quick picks")
                    .font(.headline)
                Spacer()
                Text(selectionSummaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                ForEach(FavoriteCatalogProvider.quickStartPicks, id: \.id) { item in
                    quickPickTile(item: item)
                }
            }
        }
    }

    private var favoritesSearchControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Search teams, competitions, countries, or sports", text: $query)
                    .textFieldStyle(.roundedBorder)

                if isLoadingSoccerTeams {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            HStack {
                Picker("Type", selection: $kindFilter) {
                    ForEach(OnboardingSearchKindFilter.allCases) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                .pickerStyle(.menu)

                Picker("Sport", selection: $sportFilter) {
                    ForEach(OnboardingSearchSportFilter.allCases) { sport in
                        Text(sport.rawValue).tag(sport)
                    }
                }
                .pickerStyle(.menu)

                Spacer()

                Text("\(visibleCatalogItems.count) shown")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var favoritesSelectedSection: some View {
        if !selected.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Selected")
                        .font(.headline)
                    Spacer()
                    Text(selectionSummaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                selectionPills(items: selected)
            }
        }
    }

    @ViewBuilder
    private var favoritesResultsSection: some View {
        if visibleCatalogItems.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("No results")
                    .font(.headline)
                Text("Try another sport, switch the type filter, or search by competition instead of team.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
            )
        } else {
            LazyVStack(spacing: 8) {
                ForEach(visibleCatalogItems, id: \.id) { item in
                    FavoriteCatalogRow(
                        item: item,
                        isSelected: isSelected(item),
                        onToggle: { toggle(item) }
                    )
                }
            }
        }
    }

    private var watchStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Streamed is enabled by default", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)

                Text("You can finish setup now and start using Matcha immediately. IPTV is optional and improves channel matching in Favorites & Streams.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            onboardingSummaryCard

            VStack(alignment: .leading, spacing: 10) {
                Text("Optional IPTV setup")
                    .font(.headline)

                TextField("M3U playlist URL", text: $iptvM3UURL)
                    .textFieldStyle(.roundedBorder)

                TextField("EPG URL (XMLTV)", text: $iptvEPGURL)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 8) {
                    Button("Autofill EPG from M3U") {
                        if let inferred = inferEPGURL(from: iptvM3UURL) {
                            iptvEPGURL = inferred
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(!hasM3U)

                    if hasM3U && hasEPG {
                        Label("Ready", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
            )

            Button {
                openPreferencesAction()
            } label: {
                Label("Open advanced settings", systemImage: "gearshape")
            }
            .buttonStyle(.bordered)

            Text("You can change favorites, sources, and appearance later in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var onboardingSummaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Setup summary")
                .font(.headline)

            HStack(spacing: 8) {
                onboardingMetricPill(title: "Favorites", value: "\(totalSelectedCount)")
                onboardingMetricPill(title: "Teams", value: "\(selectedTeams.count)")
                onboardingMetricPill(title: "Competitions", value: "\(selectedCompetitions.count)")
            }

            if hasFavorites {
                selectionPills(items: Array(selected.prefix(6)))
            } else {
                Text("You can finish now, but Matcha gets much better once you pick a few favorites.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
        )
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if step != .welcome {
                Button("Back") {
                    step = OnboardingStep(rawValue: max(step.rawValue - 1, 0)) ?? .welcome
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            switch step {
            case .welcome:
                Button("Skip for now") {
                    finishOnboarding()
                }
                .buttonStyle(.bordered)

                Button("Get Started") {
                    step = .favorites
                }
                .buttonStyle(.borderedProminent)
            case .favorites:
                Button("Skip for now") {
                    step = .watch
                }
                .buttonStyle(.bordered)

                Button("Continue") {
                    step = .watch
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasFavorites)
            case .watch:
                Button("Finish") {
                    finishOnboarding()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    @ViewBuilder
    private func onboardingBullet(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.green)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func quickStartChip(item: FavoriteCatalogItem) -> some View {
        Button {
            toggle(item)
        } label: {
            HStack(spacing: 6) {
                Text(item.sport == .cricket ? "Cricket" : "Soccer")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(item.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(isSelected(item) ? 0.12 : 0.05))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(isSelected(item) ? 0.18 : 0.08), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func quickPickTile(item: FavoriteCatalogItem) -> some View {
        let selected = isSelected(item)

        Button {
            toggle(item)
        } label: {
            HStack(spacing: 8) {
                VStack(spacing: 4) {
                    Image(systemName: item.sport == .cricket ? "figure.cricket" : "soccerball")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(selected ? .green : .secondary)
                        .frame(width: 24, height: 24)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(selected ? 0.12 : 0.05))
                        )
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text("\(item.sport.rawValue.capitalized) • \(item.kind.rawValue.capitalized)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(selected ? .green : .secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(selected ? 0.08 : 0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(selected ? 0.18 : 0.08), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func selectionPills(items: [FavoriteSelection]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 148), spacing: 8)], spacing: 8) {
            ForEach(items, id: \.id) { item in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Text(item.sport.rawValue.capitalized)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Button {
                        removeSelection(withID: item.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
            }
        }
    }

    @ViewBuilder
    private func onboardingMetricPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    private func loadSoccerTeamCatalogIfNeeded() async {
        guard !loadedSoccerTeams else { return }
        loadedSoccerTeams = true
        isLoadingSoccerTeams = true
        defer { isLoadingSoccerTeams = false }
        soccerTeamCatalog = await FavoriteCatalogProvider.loadSoccerTeamCatalog()
    }

    private func isSelected(_ item: FavoriteCatalogItem) -> Bool {
        selected.contains(where: { $0.id == item.id })
    }

    private func toggle(_ item: FavoriteCatalogItem) {
        if isSelected(item) {
            removeSelection(withID: item.id)
        } else {
            add(item)
        }
    }

    private func add(_ item: FavoriteCatalogItem) {
        var current = selected
        current.append(item.selection)
        favoriteSelectionsJSON = FavoriteSelectionsStore.encode(current)
    }

    private func removeSelection(withID id: String) {
        favoriteSelectionsJSON = FavoriteSelectionsStore.encode(selected.filter { $0.id != id })
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

    private func finishOnboarding() {
        FavoriteSelectionsStore.syncFeedEnables(from: favoriteSelectionsJSON)
        hasCompletedOnboarding = true
    }
}

private struct FavoriteCatalogRow: View {
    let item: FavoriteCatalogItem
    let isSelected: Bool
    let onToggle: () -> Void

    private var subtitle: String {
        var parts = [item.sport.rawValue.capitalized, item.kind.rawValue.capitalized]
        if let country = item.country, !country.isEmpty {
            parts.append(country)
        }
        return parts.joined(separator: " • ")
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(isSelected ? "Added" : "Add") {
                onToggle()
            }
            .modifier(OnboardingCatalogRowButtonStyle(isSelected: isSelected))
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
        )
    }
}

private struct OnboardingCatalogRowButtonStyle: ViewModifier {
    let isSelected: Bool

    func body(content: Content) -> some View {
        if isSelected {
            content.buttonStyle(.bordered)
        } else {
            content.buttonStyle(.borderedProminent)
        }
    }
}
