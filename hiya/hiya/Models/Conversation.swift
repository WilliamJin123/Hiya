import Foundation

struct Conversation: Codable, Sendable, Identifiable, Equatable {
    let id: UUID
    let ownerId: UUID
    let personId: UUID
    var occurredAt: Date
    var valence: Valence?
    var note: String?
    var improvementNote: String? = nil
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
        case createdAt = "created_at"
    }
}
