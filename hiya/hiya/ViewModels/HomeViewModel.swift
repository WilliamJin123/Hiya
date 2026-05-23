import Foundation
import Observation

@MainActor
@Observable
final class HomeViewModel {
    private let repo: HiyaRepository
    private(set) var profile: Profile?
    private(set) var count: Int = 0
    private(set) var todaysLog: [LoggedConversation] = []
    private(set) var streaks: StreakInfo = .zero
    private(set) var followUpSuggestions: [Person] = []
    private(set) var isLoading: Bool = false
    var errorMessage: String?

    var goal: Int { profile?.dailyGoal ?? 10 }
    var progress: Double {
        guard goal > 0 else { return 0 }
        return min(1.0, Double(count) / Double(goal))
    }
    var isGoalMet: Bool { count >= goal }
    var ringState: RingState {
        if count < goal {
            let p = goal > 0 ? Double(count) / Double(goal) : 0
            return .inProgress(count: count, goal: goal, progress: p)
        } else if count == goal {
            return .atGoal(goal: goal)
        } else {
            return .overload(count: count, goal: goal, extra: count - goal)
        }
    }

    init(repo: HiyaRepository) {
        self.repo = repo
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            if profile == nil {
                profile = try await repo.ensureSignedIn()
            }
            let (start, end) = Self.todayWindow()
            let streakSince = Calendar.current.date(byAdding: .day, value: -90, to: start) ?? start
            async let logResult = repo.todaysLog(start: start, end: end)
            async let activityResult = repo.recentConversationActivity(since: streakSince)
            async let suggestionsResult = repo.followUpSuggestions(thresholdDays: 7, limit: 3)
            let log = try await logResult
            let activity = try await activityResult
            let suggestions = try await suggestionsResult
            self.todaysLog = log
            self.count = Set(log.map(\.personId)).count
            self.streaks = StreakInfo.compute(activity: activity)
            self.followUpSuggestions = suggestions
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    static func todayWindow(now: Date = .now, calendar: Calendar = .current) -> (start: Date, end: Date) {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? now
        return (start, end)
    }
}

enum RingState: Equatable, Sendable {
    case inProgress(count: Int, goal: Int, progress: Double)
    case atGoal(goal: Int)
    case overload(count: Int, goal: Int, extra: Int)
}
