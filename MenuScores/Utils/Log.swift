import Foundation
import os

/// Lightweight wrapper around `os.Logger` so feed/network failures land in
/// Console.app (and unified logging) instead of `print`, which is invisible in
/// release builds and noisy in debug. Categorize by subsystem area.
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.menuscores"

    static let network = Logger(subsystem: subsystem, category: "network")
    static let feed = Logger(subsystem: subsystem, category: "feed")
    static let ui = Logger(subsystem: subsystem, category: "ui")
}
