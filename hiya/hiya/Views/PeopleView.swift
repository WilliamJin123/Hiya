import SwiftUI

struct PeopleView: View {
    let repo: HiyaRepository
    @State private var vm: PeopleViewModel
    @AppStorage("hiya.selectedMode") private var mode: PersonStatus = .cold
    @State private var pendingDeleteId: UUID?
    @State private var editing: Person?

    init(repo: HiyaRepository) {
        self.repo = repo
        _vm = State(initialValue: PeopleViewModel(repo: repo))
    }

    var body: some View {
        ZStack {
            Theme.bgGradient.ignoresSafeArea()
            VStack(spacing: Theme.Spacing.md) {
                Picker("Mode", selection: $mode) {
                    Text("Cold").tag(PersonStatus.cold)
                    Text("Warm").tag(PersonStatus.warm)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.sm)

                listSection
            }
        }
        .navigationTitle("People")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .sheet(item: $editing, onDismiss: { Task { await vm.load() } }) { person in
            PersonDetailSheet(repo: repo, person: person)
        }
        .confirmationDialog(
            "Delete this person?",
            isPresented: Binding(
                get: { pendingDeleteId != nil },
                set: { if !$0 { pendingDeleteId = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDeleteId
        ) { id in
            Button("Delete", role: .destructive) {
                Task {
                    await vm.delete(id)
                    pendingDeleteId = nil
                }
            }
            Button("Cancel", role: .cancel) { pendingDeleteId = nil }
        } message: { _ in
            Text("This will also delete every conversation you've logged with them.")
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
    private var listSection: some View {
        let filtered = vm.people(in: mode)
        if filtered.isEmpty {
            VStack(spacing: Theme.Spacing.sm) {
                Spacer()
                Text(mode == .cold
                     ? "No cold people.\nEveryone you've logged is warm by now."
                     : "No warm people yet.\nLog a conversation to graduate someone.")
                    .multilineTextAlignment(.center)
                    .font(Theme.FontScale.secondary())
                    .foregroundColor(Theme.textSecondary)
                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.md)
        } else {
            List {
                ForEach(filtered) { person in
                    Button {
                        editing = person
                    } label: {
                        PersonRow(person: person)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Theme.surface)
                    .listRowSeparatorTint(Theme.divider)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            pendingDeleteId = person.id
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }
}

private struct PersonRow: View {
    let person: Person

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            statusBadge
            VStack(alignment: .leading, spacing: 2) {
                Text(person.name)
                    .font(Theme.FontScale.body())
                    .foregroundColor(Theme.textPrimary)
                Text(subtitleText)
                    .font(Theme.FontScale.secondary())
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            if person.notes?.isEmpty == false {
                Image(systemName: "note.text")
                    .foregroundColor(Theme.textSecondary)
                    .font(.system(size: 12))
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var statusBadge: some View {
        Image(systemName: person.status == .cold ? "flame.fill" : "hand.wave.fill")
            .foregroundColor(person.status == .cold ? Theme.accentAmber : Theme.accentLavender)
            .font(.system(size: 14))
            .frame(width: 24)
    }

    private var subtitleText: String {
        if let notes = person.notes, !notes.isEmpty {
            return notes
        }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return "Last seen \(f.localizedString(for: person.lastLoggedAt, relativeTo: .now))"
    }
}

#Preview {
    NavigationStack {
        PeopleView(repo: MockHiyaRepository(
            people: [
                Person(id: UUID(), ownerId: UUID(), name: "Alex",
                       status: .warm, statusChangedAt: .now,
                       createdAt: .now, lastLoggedAt: .now),
                Person(id: UUID(), ownerId: UUID(), name: "Bea",
                       status: .cold, statusChangedAt: nil,
                       createdAt: .now, lastLoggedAt: .now)
            ]
        ))
    }
    .preferredColorScheme(.dark)
}
