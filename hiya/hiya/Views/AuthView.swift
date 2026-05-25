import SwiftUI

struct AuthView: View {
    let session: SessionViewModel

    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = "William Jin"

    enum Mode: String, CaseIterable { case signIn = "Sign in", createNew = "Create account" }

    private var canSubmit: Bool {
        email.contains("@") && password.count >= 6 &&
        (mode == .signIn || !displayName.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var body: some View {
        ZStack {
            Theme.bgGradient.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    Text("Hiya")
                        .font(Theme.FontScale.wordmark())
                        .foregroundStyle(Theme.accentGradient)
                        .frame(maxWidth: .infinity)
                        .padding(.top, Theme.Spacing.xl)

                    Picker("", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if mode == .createNew {
                        field("Name", text: $displayName, secure: false, keyboard: .default)
                    }
                    field("Email", text: $email, secure: false, keyboard: .emailAddress)
                    field("Password", text: $password, secure: true, keyboard: .default)

                    if let error = session.errorMessage {
                        Text(error)
                            .font(Theme.FontScale.secondary())
                            .foregroundColor(Theme.valenceNegative)
                    }

                    Button {
                        Task {
                            switch mode {
                            case .signIn: _ = await session.signIn(email: email, password: password)
                            case .createNew: _ = await session.signUp(email: email, password: password, displayName: displayName)
                            }
                        }
                    } label: {
                        Text(mode.rawValue)
                            .font(Theme.FontScale.body())
                            .foregroundColor(Theme.textOnAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(canSubmit ? Theme.accentLavender : Theme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSubmit || session.isWorking)
                }
                .padding(Theme.Spacing.md)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func field(_ placeholder: String, text: Binding<String>, secure: Bool, keyboard: UIKeyboardType) -> some View {
        Group {
            if secure {
                SecureField(placeholder, text: text)
            } else {
                TextField(placeholder, text: text)
                    .textInputAutocapitalization(keyboard == .emailAddress ? .never : .words)
                    .keyboardType(keyboard)
                    .autocorrectionDisabled(keyboard == .emailAddress)
            }
        }
        .font(Theme.FontScale.body())
        .foregroundColor(Theme.textPrimary)
        .padding(12)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }
}

#Preview {
    AuthView(session: SessionViewModel(repo: MockHiyaRepository()))
}
