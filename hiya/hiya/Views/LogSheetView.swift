import SwiftUI

struct LogSheetView: View {
    let repo: HiyaRepository
    @State private var vm: LogSheetViewModel
    @State private var showingDeleteConfirm = false
    @Environment(\.dismiss) private var dismiss

    init(
        repo: HiyaRepository,
        editing: LoggedConversation? = nil,
        preselectedPerson: Person? = nil,
        creationMode: PersonStatus = .cold
    ) {
        self.repo = repo
        _vm = State(initialValue: LogSheetViewModel(
            repo: repo,
            editing: editing,
            preselectedPerson: preselectedPerson,
            creationMode: creationMode
        ))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bgGradient.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                        personSection
                        whenSection
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
            sectionHeader("PEOPLE")
            if vm.editing != nil {
                Text(vm.searchText)
                    .font(Theme.FontScale.body())
                    .foregroundColor(Theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            } else {
                if !vm.targets.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Theme.Spacing.sm) {
                            ForEach(vm.targets) { target in
                                personChip(target)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                TextField("Add a person", text: $vm.searchText)
                    .font(Theme.FontScale.body())
                    .foregroundColor(Theme.textPrimary)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit { if vm.canAddTypedName { vm.addNew(vm.searchText) } }
                    .padding(12)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                if vm.canAddTypedName {
                    Picker("How did you meet?", selection: $vm.origin) {
                        Text("Cold approach").tag(PersonStatus.cold)
                        Text("Already knew them").tag(PersonStatus.warm)
                    }
                    .pickerStyle(.segmented)
                    .padding(.top, 4)
                }
                if !vm.filteredPeople.isEmpty || vm.canAddTypedName {
                    VStack(spacing: Theme.Spacing.xs) {
                        ForEach(vm.filteredPeople) { person in
                            Button {
                                vm.addExisting(person)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(person.name)
                                        .font(Theme.FontScale.body())
                                        .foregroundColor(Theme.textPrimary)
                                    Text(personSubtitle(person))
                                        .font(Theme.FontScale.micro())
                                        .tracking(0.5)
                                        .foregroundColor(Theme.textSecondary)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Theme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                            }
                            .buttonStyle(.plain)
                        }
                        if vm.canAddTypedName {
                            Button {
                                vm.addNew(vm.searchText)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(Theme.accentLavender)
                                    Text("Add new \u{201C}\(vm.trimmedSearch)\u{201D}")
                                        .font(Theme.FontScale.body())
                                        .foregroundColor(Theme.textPrimary)
                                    Spacer()
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

    private func personChip(_ target: LogTarget) -> some View {
        HStack(spacing: 6) {
            Text(target.displayName)
                .font(Theme.FontScale.secondary())
                .foregroundColor(Theme.textPrimary)
            if let note = target.note {
                Text("· \(note)")
                    .font(Theme.FontScale.micro())
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
                    .frame(maxWidth: 90)
            }
            Button {
                vm.removeTarget(target)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(Theme.accentLavender.opacity(0.18)))
    }

    private func personSubtitle(_ person: Person) -> String {
        if let notes = person.notes, !notes.isEmpty { return notes }
        return "Last seen \(relativeLastLogged(person.lastLoggedAt))"
    }

    private var whenSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionHeader("WHEN")
            DatePicker(
                "",
                selection: $vm.occurredAt,
                displayedComponents: [.date, .hourAndMinute]
            )
            .labelsHidden()
            .datePickerStyle(.compact)
            .tint(Theme.accentLavender)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
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
                if await vm.save() {
                    Haptics.success()
                    dismiss()
                }
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
