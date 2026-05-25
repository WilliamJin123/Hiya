import Foundation

struct Profile: Codable, Sendable, Identifiable, Equatable {
    let id: UUID
    var displayName: String?
    var dailyGoal: Int
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
        case dailyGoal = "daily_goal"
        case coldDailyGoal = "cold_daily_goal"
        case warmDailyGoal = "warm_daily_goal"
        case streakMode = "streak_mode"
        case timezone
        case createdAt = "created_at"
    }
}
