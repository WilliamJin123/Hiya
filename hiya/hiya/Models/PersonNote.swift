import Foundation

/// One dated entry in a person's note timeline. `createdAt` is the immutable
/// "learned on" date; `updatedAt` stays nil until the entry is first edited.
struct PersonNote: Codable, Sendable, Identifiable, Equatable, Hashable {
    let id: UUID
    let ownerId: UUID
    let personId: UUID
    var body: String
    let createdAt: Date
    var updatedAt: Date?

    var wasEdited: Bool { updatedAt != nil }

    enum CodingKeys: String, CodingKey {
        case id
        case ownerId = "owner_id"
        case personId = "person_id"
        case body
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
