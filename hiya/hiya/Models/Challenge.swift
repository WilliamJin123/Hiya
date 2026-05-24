import Foundation

enum ChallengeSource: String, Codable, Sendable, Equatable { case catalog, custom }

/// A started challenge instance (one row in the `challenges` table).
struct Challenge: Codable, Sendable, Identifiable, Equatable {
    let id: UUID
    let ownerId: UUID
    var title: String
    var prompt: String
    var track: ChallengeTrack
    var targetCount: Int?
    var durationDays: Int?
    var source: ChallengeSource
    var templateSlug: String?
    var startedAt: Date
    var completedAt: Date?

    var isComplete: Bool { completedAt != nil }

    /// When the challenge's window closes, if it has a duration.
    var endDate: Date? {
        guard let d = durationDays else { return nil }
        return Calendar.current.date(byAdding: .day, value: d, to: startedAt)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case ownerId = "owner_id"
        case title
        case prompt
        case track
        case targetCount = "target_count"
        case durationDays = "duration_days"
        case source
        case templateSlug = "template_slug"
        case startedAt = "started_at"
        case completedAt = "completed_at"
    }
}

/// Fields needed to start a challenge — built from a catalog template or the
/// custom form, then handed to the repository's `startChallenge`.
struct ChallengeDraft: Sendable, Equatable {
    var title: String
    var prompt: String
    var track: ChallengeTrack
    var targetCount: Int?
    var durationDays: Int?
    var source: ChallengeSource
    var templateSlug: String?

    init(template t: ChallengeTemplate) {
        title = t.title
        prompt = t.prompt
        track = t.track
        targetCount = t.targetCount
        durationDays = t.durationDays
        source = .catalog
        templateSlug = t.slug
    }

    init(title: String, prompt: String, track: ChallengeTrack, targetCount: Int?, durationDays: Int?) {
        self.title = title
        self.prompt = prompt
        self.track = track
        self.targetCount = targetCount
        self.durationDays = durationDays
        self.source = .custom
        self.templateSlug = nil
    }
}
