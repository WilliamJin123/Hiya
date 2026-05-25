import SwiftUI

struct SettingsView: View {
    let repo: HiyaRepository

    @State private var vm: SettingsViewModel
    @Environment(\.dismiss) private var dismiss

    init(repo: HiyaRepository) {
        self.repo = repo
        _vm = State(initialValue: SettingsViewModel(repo: repo))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bgGradient.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                        Text("DAILY GOALS")
                            .font(Theme.FontScale.bodyHeading())
                            .tracking(1.2)
                            .foregroundColor(Theme.textSecondary)

                        goalRow(
                            title: "Approaches",
                            subtitle: "New people each day",
                            value: $vm.coldGoal,
                            accent: Theme.accentAmber
                        )
                        goalRow(
                            title: "Catch-ups",
                            subtitle: "People you already know",
                            value: $vm.warmGoal,
                            accent: Theme.accentLavender
                        )

                        if let error = vm.errorMessage {
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
                    Text("Settings")
                        .font(Theme.FontScale.body())
                        .foregroundColor(Theme.textPrimary)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .task { await vm.load() }
    }

    private func goalRow(title: String, subtitle: String, value: Binding<Int>, accent: Color) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.FontScale.body())
                    .foregroundColor(Theme.textPrimary)
                Text(subtitle)
                    .font(Theme.FontScale.secondary())
                    .foregroundColor(Theme.textSecondary)
            }
            Spacer()
            Stepper(value: value, in: 1...50) {
                Text("\(value.wrappedValue)")
                    .font(.custom(Theme.FontName.counterMono, size: 22).weight(.semibold))
                    .foregroundColor(accent)
                    .frame(minWidth: 32, alignment: .trailing)
            }
            .labelsHidden()
            .fixedSize()
        }
        .padding(Theme.Spacing.md)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    private var saveButton: some View {
        Button {
            Task {
                await vm.save()
                if vm.didSave { dismiss() }
            }
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
        .disabled(vm.isSaving)
    }
}

#Preview {
    SettingsView(repo: MockHiyaRepository())
        .preferredColorScheme(.dark)
}
