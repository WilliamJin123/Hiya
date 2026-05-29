import SwiftUI

struct LogSheetView: View {
    let repo: HiyaRepository
    /// Called once the (background) save settles. `success` tells the parent
    /// whether to refresh + show a success toast, or surface the error string
    /// in a failure toast — the sheet itself is already dismissed, so this is
    /// the only place those signals can land.
    var onSaved: (_ success: Bool, _ errorMessage: String?) async -> Void = { _, _ in }
    @State private var vm: LogSheetViewModel
    @State private var showingDeleteConfirm = false
    @State private var locationSearch = LocationSearchModel()
    @FocusState private var locationFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(
        repo: HiyaRepository,
        editing: LoggedConversation? = nil,
        preselectedPerson: Person? = nil,
        creationMode: PersonStatus = .cold,
        onSaved: @escaping (_ success: Bool, _ errorMessage: String?) async -> Void = { _, _ in }
    ) {
        self.repo = repo
        self.onSaved = onSaved
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
                        if vm.isQuickApproach {
                            quickApproachSection
                        }
                        whenSection
                        whereSection
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
                WorkingOverlay(
                    isWorking: vm.isSaving || vm.isDeleting,
                    hint: vm.isDeleting ? "deleting…" : "saving…"
                )
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
            .task {
                if vm.editing == nil { await vm.load() }
                locationSearch.recents = vm.recentLocations
                locationSearch.start()
            }
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
                if vm.allowsQuickApproach {
                    Picker("", selection: $vm.isQuickMode) {
                        Text("Got a name").tag(false)
                        Text("Quick (no name)").tag(true)
                    }
                    .pickerStyle(.segmented)
                }
                if !vm.isQuickApproach {
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

    private var quickApproachSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Nameless attempts that still count toward your Approaches.")
                .font(Theme.FontScale.secondary())
                .foregroundColor(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Stepper(value: $vm.quickApproachCount, in: 1...20) {
                HStack {
                    Text("How many?")
                        .font(Theme.FontScale.body())
                        .foregroundColor(Theme.textPrimary)
                    Spacer()
                    Text("\(vm.quickApproachCount)")
                        .font(.custom(Theme.FontName.counterMono, size: 18).weight(.semibold))
                        .foregroundColor(Theme.coldAccent)
                        .contentTransition(.numericText())
                }
            }
            .tint(Theme.accentLavender)
            .padding(12)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        }
    }

    private var whereSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionHeader("WHERE (OPTIONAL)")
            TextField("Place or address", text: $vm.location)
                .font(Theme.FontScale.body())
                .foregroundColor(Theme.textPrimary)
                .autocorrectionDisabled()
                .focused($locationFocused)
                .padding(12)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                .onChange(of: vm.location) { _, newValue in
                    locationSearch.query = newValue
                }

            if locationFocused
                && vm.location.trimmingCharacters(in: .whitespaces).isEmpty
                && !locationSearch.recents.isEmpty {
                // Recents (Google-Maps style) when the field is focused but empty.
                VStack(spacing: Theme.Spacing.xs) {
                    ForEach(locationSearch.recents, id: \.self) { place in
                        locationRow(icon: "clock", text: place) {
                            vm.location = place
                            locationFocused = false
                        }
                    }
                }
            } else if !locationSearch.suggestions.isEmpty {
                VStack(spacing: Theme.Spacing.xs) {
                    ForEach(locationSearch.suggestions) { s in
                        locationRow(icon: "mappin.circle", text: s.displayString) {
                            vm.location = s.displayString
                            locationSearch.clear()
                            locationFocused = false
                        }
                    }
                }
            }
        }
    }

    private func locationRow(icon: String, text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).foregroundColor(Theme.textSecondary)
                Text(text)
                    .font(Theme.FontScale.secondary())
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        }
        .buttonStyle(.plain)
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
            // Dismiss-first so the user never sees a frozen sheet — the save
            // runs in the background and the parent surfaces a toast via
            // `onSaved` once the row commits (or fails). The Task captures
            // `vm` strongly, so the view model outlives the sheet teardown
            // until the work finishes. Haptic fires on the *actual* result,
            // not optimistically on tap.
            guard vm.canSave, !vm.isSaving else { return }
            Haptics.selection()
            let vmRef = vm
            let after = onSaved
            Task { @MainActor in
                let ok = await vmRef.save()
                if ok { Haptics.success() } else { Haptics.error() }
                await after(ok, ok ? nil : vmRef.errorMessage)
            }
            dismiss()
        } label: {
            Text(saveButtonTitle)
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

    private var saveButtonTitle: String {
        if vm.editing != nil { return "Update" }
        return vm.isQuickApproach ? "Log quick approach" : "Save"
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(Theme.FontScale.bodyHeading())
            .tracking(1.2)
            .foregroundColor(Theme.textSecondary)
    }

    private func relativeLastLogged(_ date: Date) -> String {
        Formatters.relative(date)
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
