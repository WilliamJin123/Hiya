import Foundation
import Observation

@MainActor
@Observable
final class OnboardingViewModel {
    private let repo: HiyaRepository

    static let pageCount = 4

    var page = 0
    var coldGoal: Int
    var warmGoal: Int
    private(set) var isSaving = false
    var errorMessage: String?

    init(repo: HiyaRepository, profile: Profile?) {
        self.repo = repo
        self.coldGoal = profile?.coldDailyGoal ?? 10
        self.warmGoal = profile?.warmDailyGoal ?? 10
    }

    var isLastPage: Bool { page == Self.pageCount - 1 }

    func next() {
        if page < Self.pageCount - 1 { page += 1 }
    }

    /// Persists the chosen goals. Returns true on success so the caller can
    /// then mark onboarding complete.
    func finish() async -> Bool {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            _ = try await repo.updateGoals(coldDailyGoal: coldGoal, warmDailyGoal: warmGoal)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
