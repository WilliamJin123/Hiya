import SwiftUI

struct HomeView: View {
    let repo: HiyaRepository
    @State private var vm: HomeViewModel
    @State private var sheetMode: LogSheetMode?
    @AppStorage("hiya.selectedMode") private var mode: PersonStatus = .cold

    init(repo: HiyaRepository) {
        self.repo = repo
        _vm = State(initialValue: HomeViewModel(repo: repo))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bgGradient.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Theme.Spacing.lg) {
                        modeToggle
                        ProgressRingView(state: vm.ringState)
                        streakLine
                        logButton
                        followUpSection
                        todaysLogSection
                    }
                    .padding(.bottom, Theme.Spacing.xl)
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.sm)
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Hiya")
                        .font(Theme.FontScale.title())
                        .foregroundColor(Theme.textPrimary)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink {
                        PeopleView(repo: repo)
                    } label: {
                        Image(systemName: "person.2.fill")
                            .foregroundColor(Theme.accentLavender)
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .task { await vm.refresh() }
            .refreshable { await vm.refresh() }
            .sheet(item: $sheetMode, onDismiss: { Task { await vm.refresh() } }) { sheet in
                switch sheet {
                case .create(let p):
                    LogSheetView(repo: repo, preselectedPerson: p)
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
        }
    }

    private var modeToggle: some View {
        Picker("Mode", selection: $mode) {
            Text("Cold").tag(PersonStatus.cold)
            Text("Warm").tag(PersonStatus.warm)
        }
        .pickerStyle(.segmented)
    }

    private var streakLine: some View {
        let value = mode == .cold ? vm.streaks.cold : vm.streaks.warm
        let color = mode == .cold ? Theme.accentAmber : Theme.accentLavender
        let icon  = mode == .cold ? "flame.fill" : "sparkles"
        let label = mode == .cold ? "day cold streak" : "day warm streak"
        return HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .foregroundColor(color)
            Text("\(value)")
                .font(.custom(Theme.FontName.counterMono, size: 22).weight(.semibold))
                .foregroundColor(Theme.textPrimary)
                .contentTransition(.numericText())
            Text(label)
                .font(Theme.FontScale.secondary())
                .foregroundColor(Theme.textSecondary)
        }
    }

    private var logButton: some View {
        Button {
            sheetMode = .create(preselect: nil)
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "plus.circle.fill")
                Text("Log a person").font(Theme.FontScale.body())
            }
            .foregroundColor(Theme.textOnAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.accentLavender)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            .shadow(color: Theme.accentLavender.opacity(0.3), radius: 14, x: 0, y: 8)
        }
        .buttonStyle(.plain)
    }

    private var filteredLog: [LoggedConversation] {
        let wantCold = (mode == .cold)
        return vm.todaysLog.filter { $0.wasColdAtTime == wantCold }
    }

    @ViewBuilder
    private var followUpSection: some View {
        if mode == .warm && !vm.followUpSuggestions.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("FOLLOW UP")
                    .font(Theme.FontScale.bodyHeading())
                    .tracking(1.2)
                    .foregroundColor(Theme.textSecondary)
                    .padding(.bottom, Theme.Spacing.sm)
                ForEach(vm.followUpSuggestions) { person in
                    Button {
                        sheetMode = .create(preselect: person)
                    } label: {
                        HStack(spacing: Theme.Spacing.md) {
                            Image(systemName: "sparkles")
                                .foregroundColor(Theme.accentLavender)
                                .font(.system(size: 14))
                                .frame(width: 24)
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
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: .now)
    }

    @ViewBuilder
    private var todaysLogSection: some View {
        let log = filteredLog
        if log.isEmpty {
            Text(mode == .cold
                 ? "No cold conversations yet today"
                 : "No warm conversations yet today")
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
    case create(preselect: Person?)
    case edit(LoggedConversation)

    var id: String {
        switch self {
        case .create(let p): p.map { "create-\($0.id.uuidString)" } ?? "create"
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
                    HStack(spacing: 6) {
                        Text(entry.personName)
                            .font(Theme.FontScale.body())
                            .foregroundColor(Theme.textPrimary)
                        if entry.wasColdAtTime {
                            Image(systemName: "flame.fill")
                                .foregroundColor(Theme.accentAmber)
                                .font(.system(size: 11))
                        }
                    }
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
        .preferredColorScheme(.dark)
}
