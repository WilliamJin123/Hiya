import Foundation

@MainActor
@Observable
final class SettingsViewModel {
    private let repo: HiyaRepository

    var coldGoal = 10
    var warmGoal = 10
    var isSaving = false
    var errorMessage: String?
    var didSave = false

    init(repo: HiyaRepository) {
        self.repo = repo
    }

    func load() async {
        do {
            let p = try await repo.ensureSignedIn()
            coldGoal = p.coldDailyGoal
            warmGoal = p.warmDailyGoal
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await repo.updateGoals(coldDailyGoal: coldGoal, warmDailyGoal: warmGoal)
            didSave = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
