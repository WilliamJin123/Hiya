import Foundation

struct Conversation: Codable, Sendable, Identifiable, Equatable {
    let id: UUID
    let ownerId: UUID
    let personId: UUID
    var occurredAt: Date
    var valence: Valence?
    var note: String?
    var improvementNote: String? = nil
    var location: String? = nil
    var wasColdAtTime: Bool = false
    /// User-set at log time (NOT derived like `wasColdAtTime`): this cold
    /// approach happened in a non-social setting where the user initiated with
    /// no pretext. Counts toward hard mode's pure-cold quota.
    var wasPureCold: Bool = false
    let createdAt: Date

    enum Valence: String, Codable, Sendable, Equatable, CaseIterable {
        case positive, neutral, negative
    }

    enum CodingKeys: String, CodingKey {
        case id
        case ownerId = "owner_id"
        case personId = "person_id"
        case occurredAt = "occurred_at"
        case valence
        case note
        case improvementNote = "improvement_note"
        case location
        case wasColdAtTime = "was_cold_at_time"
        case wasPureCold = "was_pure_cold"
        case createdAt = "created_at"
    }
}
