import Foundation
import Observation

@MainActor
@Observable
final class HomeViewModel {
    private let repo: HiyaRepository
    private(set) var profile: Profile?
    /// Unique people approached cold today. Tracked independently of warm —
    /// the two modes never share a counter.
    private(set) var coldCount: Int = 0
    /// Unique people caught up with (warm) today.
    private(set) var warmCount: Int = 0
    private(set) var todaysLog: [LoggedConversation] = []
    private(set) var streaks: StreakInfo = .zero
    private(set) var isLoading: Bool = false
    /// Flipped true once the first successful refresh lands. Drives the
    /// stale-while-revalidate seam in the view: while false we render the
    /// skeleton, after that subsequent refreshes leave content visible.
    private(set) var hasLoaded: Bool = false
    /// Increments each time a refresh detects an in-progress → at-goal
    /// transition (cold or warm). Views can `.onChange` it to fire a
    /// one-shot effect (e.g. achievement sound) without the VM knowing
    /// about audio. Stays at 0 across cold-loads — only true mid-session
    /// transitions count.
    private(set) var goalReachedTick: Int = 0
    var errorMessage: String?

    /// Per-mode daily goal — Approaches and Catch-ups never share one.
    func goal(for mode: PersonStatus) -> Int {
        switch mode {
        case .cold: return profile?.coldDailyGoal ?? 10
        case .warm: return profile?.warmDailyGoal ?? 10
        }
    }

    func count(for mode: PersonStatus) -> Int {
        mode == .cold ? coldCount : warmCount
    }

    func progress(for mode: PersonStatus) -> Double {
        let goal = goal(for: mode)
        guard goal > 0 else { return 0 }
        return min(1.0, Double(count(for: mode)) / Double(goal))
    }

    func isGoalMet(for mode: PersonStatus) -> Bool {
        count(for: mode) >= goal(for: mode)
    }

    func ringState(for mode: PersonStatus) -> RingState {
        Self.ringState(count: count(for: mode), goal: goal(for: mode))
    }

    static func ringState(count: Int, goal: Int) -> RingState {
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
            // Lazy time-based graduation: anyone who is still cold but had
            // their last log before today gets flipped to warm now. Runs in
            // parallel with the conversation/activity queries — those read
            // snapshot fields on the rows themselves and don't depend on
            // current Person.status.
            async let graduateTask: () = repo.graduatePastDuePeople(beforeLog: start)
            async let logResult = repo.conversations(start: start, end: end)
            async let activityResult = repo.recentConversationActivity(since: streakSince)
            try await graduateTask
            let log = try await logResult
            let activity = try await activityResult

            // Snapshot the pre-update ring states so we can detect the
            // in-progress → at-goal transition after counts apply. Skip on
            // cold-load (wasLoaded == false) — opening the app already at
            // 10/10 shouldn't fire the achievement chime.
            let wasLoaded = hasLoaded
            let prevCold = Self.ringState(count: coldCount, goal: goal(for: .cold))
            let prevWarm = Self.ringState(count: warmCount, goal: goal(for: .warm))

            self.todaysLog = log
            self.coldCount = Self.uniquePeople(in: log, cold: true)
            self.warmCount = Self.uniquePeople(in: log, cold: false)
            self.streaks = StreakInfo.compute(activity: activity)
            self.hasLoaded = true

            if wasLoaded {
                let newCold = Self.ringState(count: coldCount, goal: goal(for: .cold))
                let newWarm = Self.ringState(count: warmCount, goal: goal(for: .warm))
                if Self.justReachedGoal(prev: prevCold, new: newCold)
                    || Self.justReachedGoal(prev: prevWarm, new: newWarm) {
                    goalReachedTick &+= 1
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// True iff the ring went from .inProgress to .atGoal. Going .atGoal →
    /// .overload (extra logs after hitting 10) is intentionally silent.
    static func justReachedGoal(prev: RingState, new: RingState) -> Bool {
        if case .inProgress = prev, case .atGoal = new { return true }
        return false
    }

    static func uniquePeople(in log: [LoggedConversation], cold: Bool) -> Int {
        Set(log.filter { $0.wasColdAtTime == cold }.map(\.personId)).count
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
