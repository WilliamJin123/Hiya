import Foundation

struct Person: Codable, Sendable, Identifiable, Equatable, Hashable {
    let id: UUID
    let ownerId: UUID
    var name: String
    let createdAt: Date
    var lastLoggedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case ownerId = "owner_id"
        case name
        case createdAt = "created_at"
        case lastLoggedAt = "last_logged_at"
    }
}
