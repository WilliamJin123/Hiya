import Foundation
import Observation

@MainActor
@Observable
final class HomeViewModel {
    private let repo: HiyaRepository
    private(set) var profile: Profile?
    private(set) var count: Int = 0
    private(set) var todaysLog: [LoggedConversation] = []
    private(set) var isLoading: Bool = false
    var errorMessage: String?

    var goal: Int { profile?.dailyGoal ?? 10 }
    var progress: Double {
        guard goal > 0 else { return 0 }
        return min(1.0, Double(count) / Double(goal))
    }
    var isGoalMet: Bool { count >= goal }

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
            async let countResult = repo.conversationCount(start: start, end: end)
            async let logResult = repo.todaysLog(start: start, end: end)
            self.count = try await countResult
            self.todaysLog = try await logResult
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
