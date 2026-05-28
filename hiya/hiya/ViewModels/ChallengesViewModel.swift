import Foundation
import Observation

@MainActor
@Observable
final class ChallengesViewModel {
    private let repo: HiyaRepository
    private(set) var challenges: [Challenge] = []
    private(set) var recentConversations: [LoggedConversation] = []
    private(set) var isLoading = false
    /// First successful load landed — drives the SWR seam in the view.
    private(set) var hasLoaded = false
    var errorMessage: String?

    init(repo: HiyaRepository) { self.repo = repo }

    var active: [Challenge] { challenges.filter { !$0.isComplete } }
    var completed: [Challenge] { challenges.filter(\.isComplete) }

    func progress(for challenge: Challenge) -> Int {
        Self.progress(for: challenge, in: recentConversations, now: .now)
    }

    /// Active challenges relevant to a Home page: the page's own track plus
    /// any track-agnostic ones.
    func activeChallenges(for track: PersonStatus) -> [Challenge] {
        let want: ChallengeTrack = (track == .cold) ? .cold : .warm
        return active.filter { $0.track == want || $0.track == .any }
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let all = try await repo.challenges()
            // Load conversations far enough back to cover every active window.
            let earliest = all.filter { !$0.isComplete }.map(\.startedAt).min()
            let fallback = Calendar.current.date(byAdding: .day, value: -30, to: .now)!
            let start = min(earliest ?? fallback, fallback)
            let todayStart = Calendar.current.startOfDay(for: .now)
            let end = Calendar.current.date(byAdding: .day, value: 1, to: todayStart) ?? .now
            self.challenges = all
            self.recentConversations = try await repo.conversations(start: start, end: end)
            await autoComplete()
            hasLoaded = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func start(_ draft: ChallengeDraft) async {
        await mutate { _ = try await self.repo.startChallenge(draft) }
    }

    func complete(_ id: UUID) async {
        await mutate { try await self.repo.completeChallenge(id: id) }
    }

    func abandon(_ id: UUID) async {
        await mutate { try await self.repo.abandonChallenge(id: id) }
    }

    /// Mark any active targeted challenge that's reached its goal as complete.
    private func autoComplete() async {
        var changed = false
        for c in active where c.targetCount != nil {
            if progress(for: c) >= (c.targetCount ?? .max) {
                try? await repo.completeChallenge(id: c.id)
                changed = true
            }
        }
        if changed, let refreshed = try? await repo.challenges() {
            self.challenges = refreshed
        }
    }

    private func mutate(_ action: () async throws -> Void) async {
        errorMessage = nil
        do {
            try await action()
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Unique people logged on the challenge's track within its window. Only
    /// meaningful when `targetCount != nil`.
    static func progress(for challenge: Challenge, in conversations: [LoggedConversation], now: Date) -> Int {
        guard challenge.targetCount != nil else { return 0 }
        let start = challenge.startedAt
        let upper = min(now, challenge.endDate ?? now)
        let matching = conversations.filter { c in
            guard c.occurredAt >= start, c.occurredAt <= upper else { return false }
            switch challenge.track {
            case .cold: return c.wasColdAtTime
            case .warm: return !c.wasColdAtTime
            case .any:  return true
            }
        }
        return Set(matching.map(\.personId)).count
    }
}
