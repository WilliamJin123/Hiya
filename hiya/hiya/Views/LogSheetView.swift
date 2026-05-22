import SwiftUI

struct LogSheetView: View {
    let repo: HiyaRepository
    @State private var vm: LogSheetViewModel
    @Environment(\.dismiss) private var dismiss

    init(repo: HiyaRepository) {
        self.repo = repo
        _vm = State(initialValue: LogSheetViewModel(repo: repo))
    }

    var body: some View {
        NavigationStack {
            Form {
                personSection
                valenceSection
                noteSection
                if let error = vm.errorMessage {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Log a person")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            if await vm.save() { dismiss() }
                        }
                    }
                    .disabled(!vm.canSave || vm.isSaving)
                }
            }
            .task { await vm.load() }
        }
    }

    private var personSection: some View {
        Section("Person") {
            TextField("Name", text: $vm.searchText)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .onChange(of: vm.searchText) { _, _ in
                    if let selected = vm.selectedPerson, selected.name != vm.searchText {
                        vm.clearSelection()
                    }
                }
            if !vm.filteredPeople.isEmpty && vm.selectedPerson == nil {
                ForEach(vm.filteredPeople.prefix(5)) { person in
                    Button {
                        vm.select(person)
                    } label: {
                        HStack {
                            Text(person.name).foregroundStyle(.primary)
                            Spacer()
                            Text(relativeLastLogged(person.lastLoggedAt))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var valenceSection: some View {
        Section("How was it?") {
            HStack(spacing: 12) {
                ForEach(Conversation.Valence.allCases, id: \.self) { v in
                    valenceChip(v)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func valenceChip(_ v: Conversation.Valence) -> some View {
        let isSelected = vm.valence == v
        let (label, color): (String, Color) = switch v {
            case .positive: ("Good", .green)
            case .neutral: ("OK", .yellow)
            case .negative: ("Rough", .red)
        }
        return Button {
            vm.valence = isSelected ? nil : v
        } label: {
            Text(label)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(isSelected ? color.opacity(0.2) : Color.gray.opacity(0.1))
                .foregroundStyle(isSelected ? color : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var noteSection: some View {
        Section("Note (optional)") {
            TextField("", text: $vm.note, axis: .vertical)
                .lineLimit(1...4)
        }
    }

    private func relativeLastLogged(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: .now)
    }
}

#Preview {
    LogSheetView(repo: MockHiyaRepository())
}
