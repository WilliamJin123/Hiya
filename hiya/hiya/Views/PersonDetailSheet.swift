import SwiftUI

struct PersonDetailSheet: View {
    let repo: HiyaRepository
    let person: Person

    @State private var notes: String
    @State private var isSaving = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    init(repo: HiyaRepository, person: Person) {
        self.repo = repo
        self.person = person
        _notes = State(initialValue: person.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bgGradient.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                        header
                        notesSection
                        if let error = errorMessage {
                            Text(error)
                                .font(Theme.FontScale.secondary())
                                .foregroundColor(Theme.valenceNegative)
                        }
                        saveButton
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
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: person.status == .cold ? "flame.fill" : "hand.wave.fill")
                .foregroundColor(person.status == .cold ? Theme.accentAmber : Theme.accentLavender)
                .font(.system(size: 22))
            VStack(alignment: .leading, spacing: 2) {
                Text(person.status == .cold ? "Cold" : "Warm")
                    .font(Theme.FontScale.body())
                    .foregroundColor(Theme.textPrimary)
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
            TextField(
                "What should you remember about \(person.name)?",
                text: $notes,
                axis: .vertical
            )
            .font(Theme.FontScale.body())
            .foregroundColor(Theme.textPrimary)
            .lineLimit(3...12)
            .padding(12)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        }
    }

    private var saveButton: some View {
        Button {
            Task { await save() }
        } label: {
            Text("Save")
                .font(Theme.FontScale.body())
                .foregroundColor(Theme.textOnAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Theme.accentLavender)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                .shadow(color: Theme.accentLavender.opacity(0.3), radius: 14, x: 0, y: 8)
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let toSend = trimmed.isEmpty ? nil : trimmed
        do {
            try await repo.updatePersonNotes(id: person.id, notes: toSend)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
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
