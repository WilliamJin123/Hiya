import Foundation

/// Shared, reusable formatters. `DateFormatter` / `RelativeDateTimeFormatter` are
/// expensive to instantiate, so we build each once and reuse it rather than
/// allocating a fresh one on every call (these are used only on the main thread).
enum Formatters {
    /// "2h ago", "3d ago" — used for "last seen" lines.
    static let relativeShort: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    /// "May 2026" — month navigation header.
    static let monthYear: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    static func relative(_ date: Date) -> String {
        relativeShort.localizedString(for: date, relativeTo: .now)
    }
}
