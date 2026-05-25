import SwiftUI
import Charts

struct InsightsView: View {
    let repo: HiyaRepository
    @State private var vm: InsightsViewModel

    init(repo: HiyaRepository) {
        self.repo = repo
        _vm = State(initialValue: InsightsViewModel(repo: repo))
    }

    var body: some View {
        ZStack {
            Theme.bgGradient.ignoresSafeArea()
            ScrollView {
                if vm.hasAnyData {
                    VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                        activityCard
                        conversionsCard
                        valenceCard
                        lessonsCard
                    }
                    .padding(Theme.Spacing.md)
                } else {
                    emptyState
                }
            }
        }
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await vm.load() }
        .refreshable { await vm.load() }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "chart.bar")
                .font(.system(size: 32))
                .foregroundColor(Theme.textSecondary)
            Text("Log a few conversations to see your progress here.")
                .multilineTextAlignment(.center)
                .font(Theme.FontScale.secondary())
                .foregroundColor(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Spacing.xl * 2)
        .padding(.horizontal, Theme.Spacing.lg)
    }

    // MARK: - Cards

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(title)
                .font(Theme.FontScale.bodyHeading())
                .tracking(1.2)
                .foregroundColor(Theme.textSecondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    private var activityCard: some View {
        card("ACTIVITY · LAST 8 WEEKS") {
            Chart {
                ForEach(vm.weeks) { w in
                    BarMark(
                        x: .value("Week", w.weekStart, unit: .weekOfYear),
                        y: .value("Count", w.cold)
                    )
                    .foregroundStyle(by: .value("Track", "Approaches"))
                    BarMark(
                        x: .value("Week", w.weekStart, unit: .weekOfYear),
                        y: .value("Count", w.warm)
                    )
                    .foregroundStyle(by: .value("Track", "Catch-ups"))
                }
            }
            .chartForegroundStyleScale([
                "Approaches": Theme.coldAccent,
                "Catch-ups": Theme.warmAccent
            ])
            .chartLegend(position: .bottom, spacing: 8)
            .frame(height: 180)
        }
    }

    private var conversionsCard: some View {
        card("COLD → WARM") {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                Text("\(vm.becameRegulars)")
                    .font(.custom(Theme.FontName.counterMono, size: 44).weight(.semibold))
                    .foregroundColor(Theme.warmAccent)
                Text("of \(vm.strangers) strangers\nbecame regulars")
                    .font(Theme.FontScale.secondary())
                    .foregroundColor(Theme.textSecondary)
            }
            if vm.strangers > 0 {
                Text("\(Int((vm.conversionRate * 100).rounded()))% conversion")
                    .font(Theme.FontScale.micro())
                    .tracking(0.8)
                    .foregroundColor(Theme.coldAccent)
            }
        }
    }

    private var valenceCard: some View {
        let v = vm.valence
        let total = max(1, v.positive + v.neutral + v.negative)
        return card("HOW IT FELT") {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    segment(width: geo.size.width * CGFloat(v.positive) / CGFloat(total), color: Theme.valencePositive)
                    segment(width: geo.size.width * CGFloat(v.neutral) / CGFloat(total), color: Theme.valenceNeutral)
                    segment(width: geo.size.width * CGFloat(v.negative) / CGFloat(total), color: Theme.valenceNegative)
                }
            }
            .frame(height: 12)
            HStack(spacing: Theme.Spacing.md) {
                valenceLegend("Good", v.positive, Theme.valencePositive)
                valenceLegend("Okay", v.neutral, Theme.valenceNeutral)
                valenceLegend("Tough", v.negative, Theme.valenceNegative)
            }
        }
    }

    private func segment(width: CGFloat, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(color)
            .frame(width: max(0, width))
    }

    private func valenceLegend(_ label: String, _ count: Int, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("\(label) \(count)")
                .font(Theme.FontScale.micro())
                .tracking(0.6)
                .foregroundColor(Theme.textSecondary)
        }
    }

    private var lessonsCard: some View {
        card("LESSONS") {
            if vm.lessons.isEmpty {
                Text("Notes you jot on what to improve will collect here.")
                    .font(Theme.FontScale.secondary())
                    .foregroundColor(Theme.textSecondary)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(vm.lessons) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.improvementNote ?? "")
                                .font(Theme.FontScale.body())
                                .foregroundColor(Theme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("\(entry.personName) · \(entry.occurredAt.formatted(date: .abbreviated, time: .omitted))")
                                .font(Theme.FontScale.micro())
                                .tracking(0.6)
                                .foregroundColor(Theme.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                        if entry.id != vm.lessons.last?.id {
                            Theme.divider.frame(height: 1)
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        InsightsView(repo: MockHiyaRepository())
    }
    .preferredColorScheme(.dark)
}
