import SwiftUI

struct PersonDetailSheet: View {
    let repo: HiyaRepository
    let person: Person

    @State private var vm: PersonDetailViewModel
    @State private var draft = ""
    @State private var editingNote: PersonNote?
    @State private var editText = ""
    @State private var isMoving = false
    @Environment(\.dismiss) private var dismiss

    init(repo: HiyaRepository, person: Person) {
        self.repo = repo
        self.person = person
        _vm = State(initialValue: PersonDetailViewModel(repo: repo, person: person))
    }

    private var canAdd: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bgGradient.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                        header
                        notesSection
                        if person.status == .cold {
                            moveToWarmButton
                        }
                        if let error = vm.errorMessage {
                            Text(error)
                                .font(Theme.FontScale.secondary())
                                .foregroundColor(Theme.valenceNegative)
                        }
                    }
                    .padding(Theme.Spacing.md)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundColor(Theme.textSecondary)
                        .font(Theme.FontScale.body())
                }
                ToolbarItem(placement: .principal) {
                    Text(person.name)
                        .font(Theme.FontScale.body())
                        .foregroundColor(Theme.textPrimary)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .task { await vm.load() }
        .alert("Edit note", isPresented: Binding(
            get: { editingNote != nil },
            set: { if !$0 { editingNote = nil } }
        )) {
            TextField("Note", text: $editText, axis: .vertical)
            Button("Save") {
                if let n = editingNote {
                    let t = editText
                    Task { await vm.edit(n, to: t) }
                }
                editingNote = nil
            }
            Button("Cancel", role: .cancel) { editingNote = nil }
        }
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                if person.status == .cold {
                    Text("JUST MET")
                        .font(Theme.FontScale.micro())
                        .tracking(1.2)
                        .foregroundColor(Theme.accentAmber)
                }
                Text("Last seen \(relative(person.lastLoggedAt))")
                    .font(Theme.FontScale.secondary())
                    .foregroundColor(Theme.textSecondary)
            }
            Spacer()
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("NOTES")
                .font(Theme.FontScale.bodyHeading())
                .tracking(1.2)
                .foregroundColor(Theme.textSecondary)

            addRow

            if vm.notes.isEmpty {
                Text("No notes yet. Jot down what you learn about \(person.name) — each note is dated.")
                    .font(Theme.FontScale.secondary())
                    .foregroundColor(Theme.textSecondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(vm.notes) { note in
                    noteRow(note)
                }
            }
        }
    }

    private var addRow: some View {
        HStack(spacing: Theme.Spacing.sm) {
            TextField("Add a note…", text: $draft, axis: .vertical)
                .font(Theme.FontScale.body())
                .foregroundColor(Theme.textPrimary)
                .lineLimit(1...4)
                .padding(12)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            Button {
                let t = draft
                draft = ""
                Task { await vm.add(t) }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(canAdd ? Theme.accentLavender : Theme.textSecondary)
            }
            .buttonStyle(.plain)
            .disabled(!canAdd || vm.isWorking)
        }
    }

    private func noteRow(_ note: PersonNote) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(dateLine(note))
                .font(Theme.FontScale.micro())
                .tracking(0.8)
                .foregroundColor(Theme.textSecondary)
            Text(note.body)
                .font(Theme.FontScale.body())
                .foregroundColor(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .contentShape(Rectangle())
        .onTapGesture {
            editText = note.body
            editingNote = note
        }
        .contextMenu {
            Button {
                editText = note.body
                editingNote = note
            } label: { Label("Edit", systemImage: "pencil") }
            Button(role: .destructive) {
                Task { await vm.delete(note) }
            } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private var moveToWarmButton: some View {
        Button {
            Task { await moveToWarm() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.right.circle")
                Text("Move to Catch-ups")
            }
            .font(Theme.FontScale.body())
            .foregroundColor(Theme.accentLavender)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.accentLavender.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        }
        .buttonStyle(.plain)
        .disabled(isMoving)
    }

    private func moveToWarm() async {
        isMoving = true
        defer { isMoving = false }
        do {
            try await repo.updatePersonStatus(id: person.id, status: .warm)
            // Someone you already knew was never a cold approach — reclassify
            // their logs so they leave the Approaches tally (today and history).
            try await repo.reclassifyConversations(personId: person.id, wasCold: false)
            dismiss()
        } catch {
            vm.errorMessage = error.localizedDescription
        }
    }

    private func dateLine(_ note: PersonNote) -> String {
        let learned = "Learned " + note.createdAt.formatted(date: .abbreviated, time: .omitted)
        if let edited = note.updatedAt {
            return learned + " · edited " + edited.formatted(date: .abbreviated, time: .omitted)
        }
        return learned
    }

    private func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: .now)
    }
}

#Preview {
    PersonDetailSheet(
        repo: MockHiyaRepository(),
        person: Person(
            id: UUID(),
            ownerId: UUID(),
            name: "Alex",
            status: .warm,
            statusChangedAt: .now,
            notes: "Met at the climbing gym.",
            createdAt: .now,
            lastLoggedAt: .now
        )
    )
    .preferredColorScheme(.dark)
}
