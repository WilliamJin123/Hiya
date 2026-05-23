import SwiftUI

struct PeopleView: View {
    let repo: HiyaRepository
    @State private var vm: PeopleViewModel
    @State private var pendingDeleteId: UUID?
    @State private var editing: Person?

    init(repo: HiyaRepository) {
        self.repo = repo
        _vm = State(initialValue: PeopleViewModel(repo: repo))
    }

    var body: some View {
        ZStack {
            Theme.bgGradient.ignoresSafeArea()
            content
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
    private var content: some View {
        if vm.people.isEmpty {
            VStack(spacing: Theme.Spacing.sm) {
                Spacer()
                Text("Nobody yet.\nLog a conversation to get started.")
                    .multilineTextAlignment(.center)
                    .font(Theme.FontScale.secondary())
                    .foregroundColor(Theme.textSecondary)
                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.md)
        } else {
            List {
                if !vm.justMet.isEmpty {
                    Section {
                        ForEach(vm.justMet) { person in
                            personRowButton(person)
                        }
                    } header: {
                        Text("JUST MET")
                            .font(Theme.FontScale.bodyHeading())
                            .tracking(1.2)
                            .foregroundColor(Theme.accentAmber)
                    }
                }
                if !vm.recurring.isEmpty {
                    Section {
                        ForEach(vm.recurring) { person in
                            personRowButton(person)
                        }
                    } header: {
                        Text("PEOPLE")
                            .font(Theme.FontScale.bodyHeading())
                            .tracking(1.2)
                            .foregroundColor(Theme.textSecondary)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private func personRowButton(_ person: Person) -> some View {
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

private struct PersonRow: View {
    let person: Person

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
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
