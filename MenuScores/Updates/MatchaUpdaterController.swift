import AppKit
import Foundation
import Sparkle

@MainActor
final class MatchaUpdaterController: ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var automaticallyDownloadsUpdates = false
    @Published private(set) var feedURL: URL?

    let standardUpdaterController: SPUStandardUpdaterController

    init() {
        standardUpdaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        syncState()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.syncState()
            }
        }
    }

    var feedURLText: String {
        feedURL?.absoluteString ?? "Update feed will be available once the GitHub release feed is finalized."
    }

    func checkForUpdates() {
        standardUpdaterController.checkForUpdates(nil)
        syncState()
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        standardUpdaterController.updater.automaticallyChecksForUpdates = enabled
        syncState()
    }

    func setAutomaticallyDownloadsUpdates(_ enabled: Bool) {
        standardUpdaterController.updater.automaticallyDownloadsUpdates = enabled
        syncState()
    }

    private func syncState() {
        let updater = standardUpdaterController.updater
        canCheckForUpdates = updater.canCheckForUpdates
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates
        feedURL = updater.feedURL
    }
}
