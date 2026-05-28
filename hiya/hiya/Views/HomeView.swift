import SwiftUI

struct HomeView: View {
    let repo: HiyaRepository
    @State private var vm: HomeViewModel
    @State private var challengesVM: ChallengesViewModel
    @State private var sheetMode: LogSheetMode?
    @State private var showingSettings = false
    @AppStorage("hiya.selectedMode") private var mode: PersonStatus = .cold
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
                    .onChange(of: mode) { _, _ in Haptics.selection() }
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
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
            .sheet(item: $sheetMode, onDismiss: { Task { await vm.refresh(); await challengesVM.load(); await syncReminders() } }) { sheet in
                switch sheet {
                case .create(let p, let mode):
                    LogSheetView(repo: repo, preselectedPerson: p, creationMode: mode)
                case .edit(let entry):
                    LogSheetView(repo: repo, editing: entry)
                }
            }
            .alert("Something went wrong", isPresented: Binding(
                get: { vm.errorMessage != nil },
                set: { if !$0 { vm.errorMessage = nil } }
            )) {
                Button("OK") { vm.errorMessage = nil }
            } message: {
                Text(vm.errorMessage ?? "")
            }
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
                ProgressRingView(
                    state: vm.ringState(for: pageMode),
                    gradient: Theme.gradient(for: pageMode),
                    accent: Theme.accent(for: pageMode)
                )
                streakLine(for: pageMode)
                logButton(for: pageMode)
                challengeSection(for: pageMode)
                if pageMode == .warm {
                    followUpSection
                }
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
    private var followUpSection: some View {
        if !vm.followUpSuggestions.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("CHECK IN")
                    .font(Theme.FontScale.bodyHeading())
                    .tracking(1.2)
                    .foregroundColor(Theme.textSecondary)
                    .padding(.bottom, Theme.Spacing.sm)
                ForEach(vm.followUpSuggestions) { person in
                    Button {
                        sheetMode = .create(preselect: person, mode: .warm)
                    } label: {
                        HStack(spacing: Theme.Spacing.md) {
                            Circle()
                                .fill(Theme.accentLavender)
                                .frame(width: 8, height: 8)
                            Text(person.name)
                                .font(Theme.FontScale.body())
                                .foregroundColor(Theme.textPrimary)
                            Spacer()
                            Text(relativeLastLogged(person.lastLoggedAt))
                                .font(Theme.FontScale.micro())
                                .tracking(0.8)
                                .foregroundColor(Theme.textSecondary)
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if person.id != vm.followUpSuggestions.last?.id {
                        Theme.divider.frame(height: 1)
                    }
                }
            }
        }
    }

    private func relativeLastLogged(_ date: Date) -> String {
        Formatters.relative(date)
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
                    LogRow(entry: entry, onTap: { sheetMode = .edit(entry) })
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
