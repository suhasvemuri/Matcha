import Foundation

extension Collection {
    /// Bounds-checked subscript. Returns `nil` instead of crashing when `index`
    /// is out of range. Use for any ESPN/feed-derived array where the upstream
    /// shape isn't guaranteed (competitors, events, leagues, etc.).
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
