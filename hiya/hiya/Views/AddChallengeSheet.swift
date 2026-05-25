import SwiftUI

/// Presents the bundled catalog and a custom-creation form, toggled by a
/// segmented control. Calls `onStart` with a draft, then dismisses.
struct AddChallengeSheet: View {
    let onStart: (ChallengeDraft) -> Void
    @Environment(\.dismiss) private var dismiss

    private enum Tab { case catalog, custom }
    @State private var tab: Tab = .catalog

    // Custom form fields
    @State private var title = ""
    @State private var prompt = ""
    @State private var track: ChallengeTrack = .cold
    @State private var target = 0          // 0 = no target
    @State private var durationIndex = 0   // index into durationOptions

    private let durationOptions: [(label: String, days: Int?)] = [
        ("None", nil), ("3 days", 3), ("1 week", 7), ("2 weeks", 14), ("30 days", 30),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bgGradient.ignoresSafeArea()
                VStack(spacing: Theme.Spacing.md) {
                    Picker("", selection: $tab) {
                        Text("Catalog").tag(Tab.catalog)
                        Text("Custom").tag(Tab.custom)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.top, Theme.Spacing.sm)

                    if tab == .catalog {
                        catalogList
                    } else {
                        customForm
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("New challenge")
                        .font(Theme.FontScale.body())
                        .foregroundColor(Theme.textPrimary)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(Theme.textSecondary)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    private var catalogList: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.sm) {
                ForEach(ChallengeTrack.allCases, id: \.self) { trk in
                    let items = ChallengeTemplate.catalog.filter { $0.track == trk }
                    if !items.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text(trackLabel(trk).uppercased())
                                .font(Theme.FontScale.micro())
                                .tracking(1.2)
                                .foregroundColor(trackColor(trk))
                                .padding(.horizontal, Theme.Spacing.md)
                            ForEach(items) { t in
                                Button {
                                    onStart(ChallengeDraft(template: t))
                                    dismiss()
                                } label: {
                                    catalogRow(t)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, Theme.Spacing.sm)
        }
    }

    private func catalogRow(_ t: ChallengeTemplate) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(t.title)
                    .font(Theme.FontScale.body().weight(.semibold))
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                if let n = t.targetCount {
                    Text("\(n)\(t.durationDays.map { " · \($0)d" } ?? "")")
                        .font(Theme.FontScale.micro())
                        .foregroundColor(Theme.textSecondary)
                }
            }
            Text(t.prompt)
                .font(Theme.FontScale.secondary())
                .foregroundColor(Theme.textSecondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .padding(.horizontal, Theme.Spacing.md)
    }

    private var customForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                field("TITLE") {
                    TextField("e.g. Smile first", text: $title)
                        .textInputAutocapitalization(.sentences)
                        .styledInput()
                }
                field("PROMPT") {
                    TextField("What's the challenge?", text: $prompt, axis: .vertical)
                        .lineLimit(1...4)
                        .styledInput()
                }
                field("TRACK") {
                    Picker("", selection: $track) {
                        Text("Approaches").tag(ChallengeTrack.cold)
                        Text("Catch-ups").tag(ChallengeTrack.warm)
                        Text("Anytime").tag(ChallengeTrack.any)
                    }
                    .pickerStyle(.segmented)
                }
                field("TARGET (0 = none)") {
                    Stepper("\(target) \(target == 1 ? "person" : "people")", value: $target, in: 0...20)
                        .foregroundColor(Theme.textPrimary)
                }
                field("DURATION") {
                    Picker("", selection: $durationIndex) {
                        ForEach(durationOptions.indices, id: \.self) { i in
                            Text(durationOptions[i].label).tag(i)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Button {
                    let draft = ChallengeDraft(
                        title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                        prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
                        track: track,
                        targetCount: target > 0 ? target : nil,
                        durationDays: durationOptions[durationIndex].days
                    )
                    onStart(draft)
                    dismiss()
                } label: {
                    Text("Start challenge")
                        .font(Theme.FontScale.body())
                        .foregroundColor(canStart ? Theme.textOnAccent : Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(canStart ? Theme.accentLavender : Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                }
                .buttonStyle(.plain)
                .disabled(!canStart)
            }
            .padding(Theme.Spacing.md)
        }
    }

    private var canStart: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(label)
                .font(Theme.FontScale.bodyHeading())
                .tracking(1.2)
                .foregroundColor(Theme.textSecondary)
            content()
        }
    }

    private func trackLabel(_ track: ChallengeTrack) -> String {
        switch track {
        case .cold: "Approaches"
        case .warm: "Catch-ups"
        case .any:  "Anytime"
        }
    }

    private func trackColor(_ track: ChallengeTrack) -> Color {
        switch track {
        case .cold: Theme.coldAccent
        case .warm: Theme.warmAccent
        case .any:  Theme.textSecondary
        }
    }
}

private extension View {
    func styledInput() -> some View {
        self
            .font(Theme.FontScale.body())
            .foregroundColor(Theme.textPrimary)
            .padding(12)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }
}

#Preview {
    AddChallengeSheet { _ in }
        .preferredColorScheme(.dark)
}
