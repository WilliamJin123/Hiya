import Foundation

struct Profile: Codable, Sendable, Identifiable, Equatable {
    let id: UUID
    var displayName: String?
    var coldDailyGoal: Int = 10
    var warmDailyGoal: Int = 10
    var streakMode: StreakMode
    var timezone: String
    let createdAt: Date

    enum StreakMode: String, Codable, Sendable, Equatable {
        case hard, soft
    }

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case coldDailyGoal = "cold_daily_goal"
        case warmDailyGoal = "warm_daily_goal"
        case streakMode = "streak_mode"
        case timezone
        case createdAt = "created_at"
    }
}

extension Profile {
    /// Custom decoder so a dropped or not-yet-added column never breaks the
    /// app: every non-essential field falls back to its property default. (The
    /// auto-synthesized decoder ignores defaults and throws `keyNotFound`
    /// instead — which is what burned us when `daily_goal` got dropped.)
    /// Lives in an extension so the memberwise initializer is preserved.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id            = try c.decode(UUID.self, forKey: .id)
        self.displayName   = try c.decodeIfPresent(String.self, forKey: .displayName)
        self.coldDailyGoal = try c.decodeIfPresent(Int.self, forKey: .coldDailyGoal) ?? 10
        self.warmDailyGoal = try c.decodeIfPresent(Int.self, forKey: .warmDailyGoal) ?? 10
        self.streakMode    = try c.decodeIfPresent(StreakMode.self, forKey: .streakMode) ?? .hard
        self.timezone      = try c.decodeIfPresent(String.self, forKey: .timezone) ?? "UTC"
        self.createdAt     = try c.decode(Date.self, forKey: .createdAt)
    }
}
