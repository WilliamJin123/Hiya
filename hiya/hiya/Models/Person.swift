import Foundation

struct Person: Codable, Sendable, Identifiable, Equatable, Hashable {
    let id: UUID
    let ownerId: UUID
    var name: String
    var status: PersonStatus
    var statusChangedAt: Date?
    var notes: String? = nil
    var metCold: Bool = false
    var anonymous: Bool = false
    let createdAt: Date
    var lastLoggedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case ownerId = "owner_id"
        case name
        case status
        case statusChangedAt = "status_changed_at"
        case notes
        case metCold = "met_cold"
        case anonymous
        case createdAt = "created_at"
        case lastLoggedAt = "last_logged_at"
    }
}

enum PersonStatus: String, Codable, Sendable, Equatable, CaseIterable {
    case cold
    case warm
}
