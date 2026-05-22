import SwiftUI

struct HomeView: View {
    let repo: HiyaRepository
    @State private var vm: HomeViewModel
    @State private var showingLogSheet = false

    init(repo: HiyaRepository) {
        self.repo = repo
        _vm = State(initialValue: HomeViewModel(repo: repo))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                progressRing
                logButton
                todaysLogSection
                Spacer()
            }
            .padding()
            .navigationTitle("Hiya")
            .task { await vm.refresh() }
            .refreshable { await vm.refresh() }
            .sheet(isPresented: $showingLogSheet, onDismiss: { Task { await vm.refresh() } }) {
                LogSheetView(repo: repo)
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
    }

    private var progressRing: some View {
        ZStack {
            Circle()
                .stroke(.secondary.opacity(0.15), lineWidth: 18)
            Circle()
                .trim(from: 0, to: vm.progress)
                .stroke(
                    vm.isGoalMet ? AnyShapeStyle(Color.green) : AnyShapeStyle(Color.accentColor),
                    style: StrokeStyle(lineWidth: 18, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.4), value: vm.progress)
            VStack(spacing: 4) {
                Text("\(vm.count)")
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text("of \(vm.goal)")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 240, height: 240)
        .padding(.top, 24)
    }

    private var logButton: some View {
        Button {
            showingLogSheet = true
        } label: {
            Label("Log a person", systemImage: "plus.circle.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .tint(.accentColor)
    }

    @ViewBuilder
    private var todaysLogSection: some View {
        if vm.todaysLog.isEmpty {
            VStack(spacing: 8) {
                Text("No conversations yet today")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 16)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text("Today")
                    .font(.headline)
                    .padding(.bottom, 8)
                ForEach(vm.todaysLog) { entry in
                    LogRow(entry: entry)
                    if entry.id != vm.todaysLog.last?.id {
                        Divider()
                    }
                }
            }
        }
    }
}

private struct LogRow: View {
    let entry: LoggedConversation

    var body: some View {
        HStack(spacing: 12) {
            valenceIndicator
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.personName).font(.body)
                if let note = entry.note, !note.isEmpty {
                    Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Text(entry.occurredAt, style: .time)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    private var valenceIndicator: some View {
        let color: Color = switch entry.valence {
            case .positive: .green
            case .neutral: .yellow
            case .negative: .red
            case .none: .gray.opacity(0.4)
        }
        return Circle().fill(color).frame(width: 10, height: 10)
    }
}

#Preview {
    HomeView(repo: MockHiyaRepository())
}
