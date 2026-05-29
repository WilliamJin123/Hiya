import SwiftUI

struct PersonDetailSheet: View {
    let repo: HiyaRepository
    let person: Person

    @State private var vm: PersonDetailViewModel
    @State private var draft = ""
    @State private var editingNote: PersonNote?
    @State private var editText = ""
    @State private var isMoving = false
    @State private var loggingPast = false
    @State private var editingInteraction: LoggedConversation?
    @State private var renaming = false
    @State private var renameDraft = ""
    @State private var toast: ToastItem?
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
                        interactionsSection
                        logPastButton
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
                WorkingOverlay(isWorking: vm.isWorking || isMoving)
                ToastOverlay(item: $toast)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundColor(Theme.textSecondary)
                        .font(Theme.FontScale.body())
                }
                ToolbarItem(placement: .principal) {
                    Button {
                        renameDraft = vm.displayName
                        renaming = true
                    } label: {
                        HStack(spacing: 4) {
                            Text(vm.displayName)
                                .font(Theme.FontScale.body())
                                .foregroundColor(Theme.textPrimary)
                            Image(systemName: "pencil")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(Theme.textSecondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .task { await vm.load() }
        .sheet(isPresented: $loggingPast, onDismiss: { Task { await vm.load() } }) {
            LogSheetView(repo: repo, preselectedPerson: person) { ok, err in
                if ok {
                    await vm.load()
                    toast = .success("Saved")
                } else {
                    toast = .failure(err ?? "Couldn't save")
                }
            }
        }
        .sheet(item: $editingInteraction, onDismiss: { Task { await vm.load() } }) { entry in
            LogSheetView(repo: repo, editing: entry) { ok, err in
                if ok {
                    await vm.load()
                    toast = .success("Updated")
                } else {
                    toast = .failure(err ?? "Couldn't save")
                }
            }
        }
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
        .alert("Rename", isPresented: $renaming) {
            TextField("Name", text: $renameDraft)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
            Button("Save") {
                let t = renameDraft
                Task { await vm.rename(to: t) }
                renaming = false
            }
            Button("Cancel", role: .cancel) { renaming = false }
        } message: {
            Text("Fix a typo or update what you call them. Past logs will update too.")
        }
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                if person.status == .cold {
                    Text("JUST MET")
                        .font(Theme.FontScale.micro())
                        .tracking(1.2)
                        .foregroundColor(Theme.coldAccent)
                }
                Text("Last seen \(relative(person.lastLoggedAt))")
                    .font(Theme.FontScale.secondary())
                    .foregroundColor(Theme.textSecondary)
            }
            Spacer()
        }
    }

    private var interactionsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("INTERACTIONS")
                .font(Theme.FontScale.bodyHeading())
                .tracking(1.2)
                .foregroundColor(Theme.textSecondary)

            if vm.interactions.isEmpty {
                Text("No conversations logged with \(vm.displayName) yet.")
                    .font(Theme.FontScale.secondary())
                    .foregroundColor(Theme.textSecondary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(vm.interactions) { entry in
                        interactionRow(entry)
                        if entry.id != vm.interactions.last?.id {
                            Theme.divider.frame(height: 1)
                        }
                    }
                }
            }
        }
    }

    private func interactionRow(_ entry: LoggedConversation) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Circle()
                .fill(valenceColor(entry.valence))
                .frame(width: 9, height: 9)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.occurredAt.formatted(date: .abbreviated, time: .shortened))
                    .font(Theme.FontScale.body())
                    .foregroundColor(Theme.textPrimary)
                if let location = entry.location, !location.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.circle")
                            .font(.system(size: 11))
                        Text(location)
                            .font(Theme.FontScale.micro())
                            .lineLimit(1)
                    }
                    .foregroundColor(Theme.textSecondary)
                }
                if let note = entry.note, !note.isEmpty {
                    Text(note)
                        .font(Theme.FontScale.secondary())
                        .foregroundColor(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let improvement = entry.improvementNote, !improvement.isEmpty {
                    Text("To improve: \(improvement)")
                        .font(Theme.FontScale.micro())
                        .foregroundColor(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { editingInteraction = entry }
    }

    private func valenceColor(_ valence: Conversation.Valence?) -> Color {
        switch valence {
        case .positive: Theme.valencePositive
        case .neutral:  Theme.valenceNeutral
        case .negative: Theme.valenceNegative
        case .none:     Theme.valenceNone
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
                Text("No notes yet. Jot down what you learn about \(vm.displayName) — each note is dated.")
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

    private var logPastButton: some View {
        Button {
            loggingPast = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.plus")
                Text("Log a past meeting")
            }
            .font(Theme.FontScale.body())
            .foregroundColor(Theme.accentLavender)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Theme.accentLavender.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        }
        .buttonStyle(.plain)
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
            // They were never a cold approach — clear the cold origin so the
            // recompute marks all their meetings as warm catch-ups (and they
            // leave the Approaches tally, today and in history).
            try await repo.updatePersonMetCold(id: person.id, metCold: false)
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
        Formatters.relative(date)
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
