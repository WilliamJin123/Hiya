import SwiftUI

struct HomeView: View {
    let repo: HiyaRepository
    @State private var vm: HomeViewModel
    @State private var challengesVM: ChallengesViewModel
    @State private var sheetMode: LogSheetMode?
    @State private var showingSettings = false
    @AppStorage("hiya.selectedMode") private var mode: PersonStatus = .cold
    @AppStorage(HardMode.defaultsKey) private var hardMode = false
    @Environment(NotificationManager.self) private var notifications
    @Environment(\.scenePhase) private var scenePhase

    init(repo: HiyaRepository) {
        self.repo = repo
        _vm = State(initialValue: HomeViewModel(repo: repo))
        _challengesVM = State(initialValue: ChallengesViewModel(repo: repo))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bgGradient.ignoresSafeArea()
                VStack(spacing: 0) {
                    modeToggle
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.top, Theme.Spacing.sm)
                        .padding(.bottom, Theme.Spacing.md)
                    TabView(selection: $mode) {
                        pageContent(for: .cold).tag(PersonStatus.cold)
                        pageContent(for: .warm).tag(PersonStatus.warm)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .animation(.easeInOut(duration: 0.22), value: mode)
                    .onChange(of: mode) { _, _ in
                        Haptics.selection()
                        SoundEngine.shared.play(.modeSwitch)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        SoundEngine.shared.play(.sheetOpen)
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .foregroundColor(Theme.accentLavender)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("Hiya")
                        .font(Theme.FontScale.wordmark())
                        .tracking(0.5)
                        .foregroundStyle(Theme.accentGradient)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink {
                        ChallengesView(repo: repo)
                    } label: {
                        Image(systemName: "target")
                            .foregroundColor(Theme.accentLavender)
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingSettings, onDismiss: { Task { await vm.refresh(); await syncReminders() } }) {
                SettingsView(repo: repo)
            }
            .task { await vm.refresh(); await challengesVM.load(); await syncReminders() }
            .refreshable { await vm.refresh(); await challengesVM.load(); await syncReminders() }
            .onChange(of: vm.goalReachedTick) { _, _ in
                SoundEngine.shared.play(.achievement)
            }
            .sheet(item: $sheetMode, onDismiss: { Task { await vm.refresh(); await challengesVM.load(); await syncReminders() } }) { sheet in
                // The post-save refresh runs EXACTLY ONCE, in the .sheet onDismiss
                // above (post-commit, since save dismisses after it finishes). Doing
                // it here too fired a SECOND copy concurrently — and refresh/load's
                // `await repo.…` calls leave the main actor and hit the shared
                // Supabase client in parallel, which intermittently corrupted the
                // heap and crashed a later render (swift_unknownObjectRetain). Delete
                // only fires it once, which is why delete never crashed. onSaved now
                // only surfaces a failure (via the alert below); no refresh here.
                switch sheet {
                case .create(let p, let mode):
                    LogSheetView(repo: repo, preselectedPerson: p, creationMode: mode) { ok, err in
                        if !ok { vm.errorMessage = err ?? "Couldn't save" }
                    }
                case .edit(let entry):
                    LogSheetView(repo: repo, editing: entry) { ok, err in
                        if !ok { vm.errorMessage = err ?? "Couldn't save" }
                    }
                }
            }
            // NO modal `.alert` here. When an operation errored, `errorMessage`
            // flipped to non-nil from inside an async callback that resumes
            // *during* a SwiftUI render pass — SwiftUI then tried to present the
            // alert re-entrantly (ViewRendererHost.render → preferencesDidChange
            // → UIKitDialogBridge.showNewAlert) and crashed at 0x1 in Text
            // resolution. This is a presentation-lifecycle crash (both Address
            // and Thread Sanitizer are clean), and it's why the old toast crashed
            // the same way. Errors are surfaced non-modally instead — see the
            // inline banner in `pageContent`. The underlying errors (a flaky/
            // expired anonymous session forcing a main-thread-hanging refresh in
            // supabase-swift) are the real fix, tracked separately.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await vm.refresh(); await syncReminders() }
                }
            }
        }
    }

    private func syncReminders() async {
        await notifications.refresh(goalMetToday: vm.isGoalMet(for: .cold))
    }

    private var modeToggle: some View {
        HStack(spacing: 4) {
            modeButton(.cold, label: "Approaches", color: Theme.coldAccent)
            modeButton(.warm, label: "Catch-ups", color: Theme.warmAccent)
        }
        .padding(4)
        .background(Capsule().fill(Theme.surface))
    }

    private func modeButton(_ target: PersonStatus, label: String, color: Color) -> some View {
        let isActive = mode == target
        return Button {
            withAnimation(.easeInOut(duration: 0.22)) { mode = target }
        } label: {
            Text(label)
                .font(Theme.FontScale.body().weight(isActive ? .semibold : .medium))
                .foregroundColor(isActive ? Theme.textOnAccent : color.opacity(0.7))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(isActive ? color : Color.clear)
                        .shadow(color: isActive ? color.opacity(0.4) : .clear, radius: 8, x: 0, y: 4)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func pageContent(for pageMode: PersonStatus) -> some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                if vm.errorMessage != nil { errorBanner }
                ProgressRingView(
                    state: vm.ringState(for: pageMode),
                    gradient: Theme.gradient(for: pageMode),
                    accent: Theme.accent(for: pageMode),
                    innerRing: (pageMode == .cold && hardMode)
                        ? .init(
                            progress: vm.pureColdProgress,
                            count: vm.pureColdCount,
                            goal: vm.pureColdGoal,
                            accent: Theme.pureColdAccent)
                        : nil
                )
                streakLine(for: pageMode)
                logButton(for: pageMode)
                challengeSection(for: pageMode)
                todaysLogSection(for: pageMode)
            }
            .padding(.top, Theme.Spacing.lg)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .delayedLoading(isLoading: vm.isLoading, hasLoaded: vm.hasLoaded) {
            ScrollView { HomeSkeleton() }
        }
    }

    /// Non-modal error surface. Renders a STATIC string, never the raw
    /// `errorMessage` — supabase error values can carry a String whose storage
    /// is bad, which crashes when SwiftUI bridges it to NSString
    /// (swift_unknownObjectRetain at 0x1). `errorMessage` is used purely as a
    /// flag. No `.transition` / `withAnimation`: a plain conditional view in the
    /// hierarchy is a normal data-driven re-render, not a re-entrant
    /// presentation, so it can't trip the dialog-bridge crash the alert did.
    private var errorBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 13, weight: .semibold))
            Text("Couldn't sync just now. Pull down to refresh.")
                .font(Theme.FontScale.secondary())
            Spacer()
            Button { vm.errorMessage = nil } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
        }
        .foregroundColor(Theme.textSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }

    private func streakLine(for pageMode: PersonStatus) -> some View {
        let value = pageMode == .cold ? vm.streaks.cold : vm.streaks.warm
        let color = Theme.accent(for: pageMode)
        let label = pageMode == .cold ? "day approach streak" : "day catch-up streak"
        let icon = pageMode == .cold ? "flame.fill" : "heart.fill"
        return HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(color)
                .shadow(color: color.opacity(0.55), radius: 8)
            Text("\(value)")
                .font(.custom(Theme.FontName.counterMono, size: 32).weight(.semibold))
                .foregroundColor(color)
                .contentTransition(.numericText())
                .shadow(color: color.opacity(0.35), radius: 10)
            Text(label)
                .font(Theme.FontScale.secondary())
                .foregroundColor(Theme.textSecondary)
        }
    }

    private func logButton(for pageMode: PersonStatus) -> some View {
        let accent = Theme.accent(for: pageMode)
        return Button {
            SoundEngine.shared.play(.sheetOpen)
            sheetMode = .create(preselect: nil, mode: pageMode)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .bold))
                Text("Log")
                    .font(Theme.FontScale.body().weight(.semibold))
            }
            .foregroundColor(Theme.textOnAccent)
            .padding(.horizontal, 32)
            .padding(.vertical, 12)
            .background(accent)
            .clipShape(Capsule())
            .shadow(color: accent.opacity(0.45), radius: 14, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }

    private func filteredLog(for pageMode: PersonStatus) -> [LoggedConversation] {
        let wantCold = (pageMode == .cold)
        return vm.todaysLog.filter { $0.wasColdAtTime == wantCold }
    }

    @ViewBuilder
    private func challengeSection(for pageMode: PersonStatus) -> some View {
        let items = challengesVM.activeChallenges(for: pageMode)
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("CHALLENGE")
                    .font(Theme.FontScale.bodyHeading())
                    .tracking(1.2)
                    .foregroundColor(Theme.textSecondary)
                    .padding(.bottom, Theme.Spacing.sm)
                ForEach(items) { challenge in
                    NavigationLink {
                        ChallengesView(repo: repo)
                    } label: {
                        challengeRow(challenge)
                    }
                    .buttonStyle(.plain)
                    if challenge.id != items.last?.id {
                        Theme.divider.frame(height: 1)
                    }
                }
            }
        }
    }

    private func challengeRow(_ challenge: Challenge) -> some View {
        let accent = challenge.track == .warm ? Theme.accentAmber : Theme.accentLavender
        return HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "target")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(challenge.title)
                    .font(Theme.FontScale.body())
                    .foregroundColor(Theme.textPrimary)
                Text(challenge.prompt)
                    .font(Theme.FontScale.secondary())
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            if let target = challenge.targetCount {
                Text("\(challengesVM.progress(for: challenge))/\(target)")
                    .font(Theme.FontScale.micro())
                    .tracking(0.8)
                    .foregroundColor(accent)
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func todaysLogSection(for pageMode: PersonStatus) -> some View {
        let log = filteredLog(for: pageMode)
        if log.isEmpty {
            Text(pageMode == .cold
                 ? "No approaches yet today"
                 : "No catch-ups yet today")
                .font(Theme.FontScale.secondary())
                .foregroundColor(Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.top, Theme.Spacing.md)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text("TODAY")
                    .font(Theme.FontScale.bodyHeading())
                    .tracking(1.2)
                    .foregroundColor(Theme.textSecondary)
                    .padding(.bottom, Theme.Spacing.sm)
                ForEach(log) { entry in
                    LogRow(entry: entry, onTap: {
                        SoundEngine.shared.play(.sheetOpen)
                        sheetMode = .edit(entry)
                    })
                    if entry.id != log.last?.id {
                        Theme.divider.frame(height: 1)
                    }
                }
            }
        }
    }
}

enum LogSheetMode: Identifiable {
    case create(preselect: Person?, mode: PersonStatus)
    case edit(LoggedConversation)

    var id: String {
        switch self {
        case .create(let p, let mode): p.map { "create-\($0.id.uuidString)" } ?? "create-\(mode.rawValue)"
        case .edit(let c): "edit-\(c.id.uuidString)"
        }
    }
}

private struct LogRow: View {
    let entry: LoggedConversation
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Theme.Spacing.md) {
                Circle()
                    .fill(valenceColor)
                    .frame(width: 9, height: 9)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.personName)
                        .font(Theme.FontScale.body())
                        .foregroundColor(Theme.textPrimary)
                    if let note = entry.note, !note.isEmpty {
                        Text(note)
                            .font(Theme.FontScale.secondary())
                            .foregroundColor(Theme.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Text(entry.occurredAt, style: .time)
                    .font(Theme.FontScale.micro())
                    .tracking(0.8)
                    .foregroundColor(Theme.textSecondary)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var valenceColor: Color {
        switch entry.valence {
        case .positive: Theme.valencePositive
        case .neutral:  Theme.valenceNeutral
        case .negative: Theme.valenceNegative
        case .none:     Theme.valenceNone
        }
    }
}

#Preview {
    HomeView(repo: MockHiyaRepository())
        .environment(NotificationManager(scheduler: MockNotificationScheduler()))
        .preferredColorScheme(.dark)
}
