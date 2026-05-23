import SwiftUI

struct LogSheetView: View {
    let repo: HiyaRepository
    @State private var vm: LogSheetViewModel
    @State private var showingDeleteConfirm = false
    @Environment(\.dismiss) private var dismiss

    init(
        repo: HiyaRepository,
        editing: LoggedConversation? = nil,
        preselectedPerson: Person? = nil
    ) {
        self.repo = repo
        _vm = State(initialValue: LogSheetViewModel(
            repo: repo,
            editing: editing,
            preselectedPerson: preselectedPerson
        ))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bgGradient.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                        personSection
                        valenceSection
                        improvementSection
                        noteSection
                        if let error = vm.errorMessage {
                            Text(error)
                                .font(Theme.FontScale.secondary())
                                .foregroundColor(Theme.valenceNegative)
                        }
                        saveButton
                        if vm.editing != nil {
                            deleteButton
                        }
                    }
                    .padding(Theme.Spacing.md)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(Theme.textSecondary)
                        .font(Theme.FontScale.body())
                }
                ToolbarItem(placement: .principal) {
                    Text(vm.editing == nil ? "Log a person" : "Edit log")
                        .font(Theme.FontScale.body())
                        .foregroundColor(Theme.textPrimary)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .task { if vm.editing == nil { await vm.load() } }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var personSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionHeader("PERSON")
            if vm.editing != nil {
                Text(vm.searchText)
                    .font(Theme.FontScale.body())
                    .foregroundColor(Theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            } else {
                TextField("Name", text: $vm.searchText)
                    .font(Theme.FontScale.body())
                    .foregroundColor(Theme.textPrimary)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                    .onChange(of: vm.searchText) { _, _ in
                        if let selected = vm.selectedPerson, selected.name != vm.searchText {
                            vm.clearSelection()
                        }
                    }
                if !vm.filteredPeople.isEmpty && vm.selectedPerson == nil {
                    VStack(spacing: Theme.Spacing.xs) {
                        ForEach(vm.filteredPeople) { person in
                            Button {
                                vm.select(person)
                            } label: {
                                HStack {
                                    Text(person.name)
                                        .font(Theme.FontScale.body())
                                        .foregroundColor(Theme.textPrimary)
                                    Spacer()
                                    Text(relativeLastLogged(person.lastLoggedAt))
                                        .font(Theme.FontScale.micro())
                                        .tracking(0.8)
                                        .foregroundColor(Theme.textSecondary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Theme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var valenceSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionHeader("HOW WAS IT?")
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(Conversation.Valence.allCases, id: \.self) { v in
                    valenceChip(v)
                }
            }
        }
    }

    private func valenceChip(_ v: Conversation.Valence) -> some View {
        let isSelected = vm.valence == v
        let (label, color): (String, Color) = switch v {
            case .positive: ("Good",  Theme.valencePositive)
            case .neutral:  ("OK",    Theme.valenceNeutral)
            case .negative: ("Rough", Theme.valenceNegative)
        }
        return Button {
            vm.valence = isSelected ? nil : v
        } label: {
            Text(label)
                .font(Theme.FontScale.body())
                .foregroundColor(isSelected ? color : Theme.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(isSelected ? color.opacity(0.18) : Theme.surface)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var improvementSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionHeader("WHAT COULD'VE BEEN BETTER? (OPTIONAL)")
            TextField("", text: $vm.improvementNote, axis: .vertical)
                .font(Theme.FontScale.body())
                .foregroundColor(Theme.textPrimary)
                .lineLimit(1...4)
                .padding(12)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        }
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionHeader("NOTE (OPTIONAL)")
            TextField("", text: $vm.note, axis: .vertical)
                .font(Theme.FontScale.body())
                .foregroundColor(Theme.textPrimary)
                .lineLimit(1...4)
                .padding(12)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        }
    }

    private var saveButton: some View {
        Button {
            Task {
                if await vm.save() { dismiss() }
            }
        } label: {
            Text(vm.editing == nil ? "Save" : "Update")
                .font(Theme.FontScale.body())
                .foregroundColor(vm.canSave ? Theme.textOnAccent : Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(vm.canSave ? Theme.accentLavender : Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                .shadow(
                    color: vm.canSave ? Theme.accentLavender.opacity(0.3) : .clear,
                    radius: 14, x: 0, y: 8
                )
        }
        .buttonStyle(.plain)
        .disabled(!vm.canSave || vm.isSaving)
    }

    private var deleteButton: some View {
        Button {
            showingDeleteConfirm = true
        } label: {
            Text("Delete")
                .font(Theme.FontScale.body())
                .foregroundColor(Theme.valenceNegative)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        }
        .buttonStyle(.plain)
        .disabled(vm.isDeleting)
        .confirmationDialog(
            "Delete this entry?",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task {
                    if await vm.delete() { dismiss() }
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This can't be undone.")
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(Theme.FontScale.bodyHeading())
            .tracking(1.2)
            .foregroundColor(Theme.textSecondary)
    }

    private func relativeLastLogged(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: .now)
    }
}

#Preview("Create") {
    LogSheetView(repo: MockHiyaRepository())
        .preferredColorScheme(.dark)
}

#Preview("Edit") {
    LogSheetView(
        repo: MockHiyaRepository(),
        editing: LoggedConversation(
            id: UUID(),
            personId: UUID(),
            personName: "Alex",
            occurredAt: .now,
            valence: .positive,
            note: "lunch",
            improvementNote: "be more present"
        )
    )
    .preferredColorScheme(.dark)
}
