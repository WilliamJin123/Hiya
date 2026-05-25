import SwiftUI

struct SettingsView: View {
    let repo: HiyaRepository

    @State private var vm: SettingsViewModel
    @Environment(SessionViewModel.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var claimEmail = ""
    @State private var claimPassword = ""
    @State private var nameDraft = ""

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
                        accountSection

                        Text("DAILY GOALS")
                            .font(Theme.FontScale.bodyHeading())
                            .tracking(1.2)
                            .foregroundColor(Theme.textSecondary)

                        goalRow(
                            title: "Approaches",
                            subtitle: "New people each day",
                            value: $vm.coldGoal,
                            accent: Theme.coldAccent
                        )
                        goalRow(
                            title: "Catch-ups",
                            subtitle: "People you already know",
                            value: $vm.warmGoal,
                            accent: Theme.warmAccent
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
        .task {
            await vm.load()
            nameDraft = session.profile?.displayName ?? "William Jin"
        }
    }

    @ViewBuilder
    private var accountSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("ACCOUNT")
                .font(Theme.FontScale.bodyHeading())
                .tracking(1.2)
                .foregroundColor(Theme.textSecondary)

            if session.account?.isAnonymous == false {
                permanentAccountView
            } else {
                claimAccountView
            }

            if let error = session.errorMessage {
                Text(error)
                    .font(Theme.FontScale.secondary())
                    .foregroundColor(Theme.valenceNegative)
            }
        }
    }

    private var permanentAccountView: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                TextField("Your name", text: $nameDraft)
                    .font(Theme.FontScale.body())
                    .foregroundColor(Theme.textPrimary)
                    .padding(12)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                Button("Save") {
                    Task { _ = await session.updateDisplayName(nameDraft) }
                }
                .foregroundColor(Theme.accentLavender)
                .disabled(nameDraft.trimmingCharacters(in: .whitespaces).isEmpty || session.isWorking)
            }
            Text(session.account?.email ?? "")
                .font(Theme.FontScale.secondary())
                .foregroundColor(Theme.textSecondary)

            Button {
                Task { await session.signOut() }
            } label: {
                Text("Sign out")
                    .font(Theme.FontScale.body())
                    .foregroundColor(Theme.valenceNegative)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            }
            .buttonStyle(.plain)
        }
    }

    private var claimAccountView: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Create an account to keep your data safe and sign in on other devices. All your current logs stay yours.")
                .font(Theme.FontScale.secondary())
                .foregroundColor(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Name", text: $nameDraft)
                .textInputAutocapitalization(.words)
                .padding(12).background(Theme.surface).clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                .foregroundColor(Theme.textPrimary)
            TextField("Email", text: $claimEmail)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled()
                .padding(12).background(Theme.surface).clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                .foregroundColor(Theme.textPrimary)
            SecureField("Password", text: $claimPassword)
                .padding(12).background(Theme.surface).clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                .foregroundColor(Theme.textPrimary)
            Button {
                Task { _ = await session.claim(email: claimEmail, password: claimPassword, displayName: nameDraft) }
            } label: {
                Text("Create account")
                    .font(Theme.FontScale.body())
                    .foregroundColor(Theme.textOnAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(canClaim ? Theme.accentLavender : Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            }
            .buttonStyle(.plain)
            .disabled(!canClaim || session.isWorking)
        }
    }

    private var canClaim: Bool {
        claimEmail.contains("@") && claimPassword.count >= 6 &&
        !nameDraft.trimmingCharacters(in: .whitespaces).isEmpty
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
            Text("\(value.wrappedValue)")
                .font(.custom(Theme.FontName.counterMono, size: 22).weight(.semibold))
                .foregroundColor(accent)
                .frame(minWidth: 32, alignment: .trailing)
                .contentTransition(.numericText())
            Stepper("", value: value, in: 1...50)
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
        .environment(SessionViewModel(repo: MockHiyaRepository()))
        .preferredColorScheme(.dark)
}
