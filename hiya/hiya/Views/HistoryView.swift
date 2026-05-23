import SwiftUI

struct HistoryView: View {
    let repo: HiyaRepository
    @State private var vm: HistoryViewModel
    @State private var editing: LoggedConversation?

    init(repo: HiyaRepository) {
        self.repo = repo
        _vm = State(initialValue: HistoryViewModel(repo: repo))
    }

    var body: some View {
        ZStack {
            Theme.bgGradient.ignoresSafeArea()
            content
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .sheet(item: $editing, onDismiss: { Task { await vm.load() } }) { entry in
            LogSheetView(repo: repo, editing: entry)
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

    @ViewBuilder
    private var content: some View {
        if vm.sections.isEmpty {
            VStack(spacing: Theme.Spacing.sm) {
                Spacer()
                Text("Nothing here yet.\nYesterday's logs will show up tomorrow.")
                    .multilineTextAlignment(.center)
                    .font(Theme.FontScale.secondary())
                    .foregroundColor(Theme.textSecondary)
                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.md)
        } else {
            List {
                ForEach(vm.sections) { section in
                    Section {
                        ForEach(section.entries) { entry in
                            Button {
                                editing = entry
                            } label: {
                                EntryRow(entry: entry)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Theme.surface)
                            .listRowSeparatorTint(Theme.divider)
                        }
                    } header: {
                        DayHeader(section: section)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }
}

private struct DayHeader: View {
    let section: DaySection

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f
    }()

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(Self.dateFormatter.string(from: section.date).uppercased())
                .font(Theme.FontScale.bodyHeading())
                .tracking(1.2)
                .foregroundColor(Theme.textSecondary)
            Spacer()
            if section.coldCount > 0 {
                Text("\(section.coldCount) cold")
                    .font(Theme.FontScale.micro())
                    .tracking(0.8)
                    .foregroundColor(Theme.accentAmber)
            }
            Text("\(section.uniquePeopleCount) · \(section.totalCount) log\(section.totalCount == 1 ? "" : "s")")
                .font(Theme.FontScale.micro())
                .tracking(0.8)
                .foregroundColor(Theme.textSecondary)
        }
        .padding(.vertical, Theme.Spacing.xs)
    }
}

private struct EntryRow: View {
    let entry: LoggedConversation

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(entry.wasColdAtTime ? Theme.accentAmber : Color.clear)
                .frame(width: 3)
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
                            .lineLimit(2)
                    }
                }
                Spacer()
                Text(entry.occurredAt, style: .time)
                    .font(Theme.FontScale.micro())
                    .tracking(0.8)
                    .foregroundColor(Theme.textSecondary)
            }
            .padding(.leading, Theme.Spacing.sm)
            .padding(.vertical, 4)
        }
        .contentShape(Rectangle())
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
    NavigationStack {
        HistoryView(repo: MockHiyaRepository())
    }
    .preferredColorScheme(.dark)
}
