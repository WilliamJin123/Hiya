import SwiftUI

struct ChallengesView: View {
    let repo: HiyaRepository
    @State private var vm: ChallengesViewModel
    @State private var showingAdd = false

    init(repo: HiyaRepository) {
        self.repo = repo
        _vm = State(initialValue: ChallengesViewModel(repo: repo))
    }

    var body: some View {
        ZStack {
            Theme.bgGradient.ignoresSafeArea()
            content
        }
        .navigationTitle("Challenges")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showingAdd = true } label: {
                    Image(systemName: "plus").foregroundColor(Theme.accentLavender)
                }
            }
        }
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .sheet(isPresented: $showingAdd, onDismiss: { Task { await vm.load() } }) {
            AddChallengeSheet { draft in
                Task { await vm.start(draft) }
            }
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("OK") { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        if vm.active.isEmpty && vm.completed.isEmpty {
            VStack(spacing: Theme.Spacing.sm) {
                Spacer()
                Text("No challenges yet.\nTap + to start one.")
                    .multilineTextAlignment(.center)
                    .font(Theme.FontScale.secondary())
                    .foregroundColor(Theme.textSecondary)
                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.md)
        } else {
            List {
                if !vm.active.isEmpty {
                    Section {
                        ForEach(vm.active) { activeCard($0) }
                    } header: {
                        sectionHeader("ACTIVE")
                    }
                }
                if !vm.completed.isEmpty {
                    Section {
                        ForEach(vm.completed) { completedRow($0) }
                    } header: {
                        sectionHeader("DONE")
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func activeCard(_ c: Challenge) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            trackChip(c.track)
            Text(c.title)
                .font(Theme.FontScale.body().weight(.semibold))
                .foregroundColor(Theme.textPrimary)
            Text(c.prompt)
                .font(Theme.FontScale.secondary())
                .foregroundColor(Theme.textSecondary)
            if let target = c.targetCount {
                let p = vm.progress(for: c)
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: Double(min(p, target)), total: Double(target))
                        .tint(trackColor(c.track))
                    Text("\(p) / \(target)")
                        .font(Theme.FontScale.micro())
                        .foregroundColor(Theme.textSecondary)
                }
            }
            Button {
                Task { await vm.complete(c.id) }
            } label: {
                Text("Mark done")
                    .font(Theme.FontScale.micro())
                    .foregroundColor(Theme.textOnAccent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(trackColor(c.track))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        .listRowBackground(Theme.surface)
        .listRowSeparatorTint(Theme.divider)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                Task { await vm.abandon(c.id) }
            } label: {
                Label("Abandon", systemImage: "trash")
            }
        }
    }

    private func completedRow(_ c: Challenge) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(Theme.valencePositive)
            Text(c.title)
                .font(Theme.FontScale.body())
                .foregroundColor(Theme.textSecondary)
            Spacer()
        }
        .padding(.vertical, 4)
        .listRowBackground(Theme.surface)
        .listRowSeparatorTint(Theme.divider)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                Task { await vm.abandon(c.id) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func trackChip(_ track: ChallengeTrack) -> some View {
        Text(trackLabel(track).uppercased())
            .font(Theme.FontScale.micro())
            .tracking(1.0)
            .foregroundColor(trackColor(track))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(trackColor(track).opacity(0.15)))
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(Theme.FontScale.bodyHeading())
            .tracking(1.2)
            .foregroundColor(Theme.textSecondary)
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
        case .cold: Theme.accentAmber
        case .warm: Theme.accentLavender
        case .any:  Theme.textSecondary
        }
    }
}

#Preview {
    NavigationStack {
        ChallengesView(repo: MockHiyaRepository())
    }
    .preferredColorScheme(.dark)
}
