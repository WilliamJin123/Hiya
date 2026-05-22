import SwiftUI

struct HomeView: View {
    let repo: HiyaRepository
    @State private var vm: HomeViewModel
    @State private var sheetMode: LogSheetMode?

    init(repo: HiyaRepository) {
        self.repo = repo
        _vm = State(initialValue: HomeViewModel(repo: repo))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bgGradient.ignoresSafeArea()

                VStack(spacing: Theme.Spacing.xl) {
                    ProgressRingView(state: vm.ringState)
                        .padding(.top, Theme.Spacing.lg)
                    logButton
                    todaysLogSection
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Theme.Spacing.md)
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Hiya")
                        .font(Theme.FontScale.title())
                        .foregroundColor(Theme.textPrimary)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .task { await vm.refresh() }
            .refreshable { await vm.refresh() }
            .sheet(item: $sheetMode, onDismiss: { Task { await vm.refresh() } }) { mode in
                switch mode {
                case .create:
                    LogSheetView(repo: repo)
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

    private var logButton: some View {
        Button {
            sheetMode = .create
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

    @ViewBuilder
    private var todaysLogSection: some View {
        if vm.todaysLog.isEmpty {
            Text("No conversations yet today")
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
                ForEach(vm.todaysLog) { entry in
                    LogRow(entry: entry, onTap: { sheetMode = .edit(entry) })
                    if entry.id != vm.todaysLog.last?.id {
                        Theme.divider.frame(height: 1)
                    }
                }
            }
        }
    }
}

enum LogSheetMode: Identifiable {
    case create
    case edit(LoggedConversation)

    var id: String {
        switch self {
        case .create: "create"
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
        .preferredColorScheme(.dark)
}
