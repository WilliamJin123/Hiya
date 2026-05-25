import SwiftUI

struct ProgressRingView: View {
    let state: RingState
    var gradient: LinearGradient = Theme.accentGradient
    var accent: Color = Theme.accentAmber

    @State private var burstToken = 0
    @State private var wasAtGoal = false

    var body: some View {
        ZStack {
            Circle().stroke(Theme.ringTrack, lineWidth: 18)

            Circle()
                .trim(from: 0, to: fillAmount)
                .stroke(gradient, style: StrokeStyle(lineWidth: 18, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.4), value: fillAmount)

            centerContent
                .id(state.kind)
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
                .animation(.spring(response: 0.45, dampingFraction: 0.7), value: state.kind)
        }
        .frame(width: 240, height: 240)
        .shadow(color: glowColor, radius: Theme.Glow.blur, x: 0, y: 0)
        .overlay {
            if isAtGoal {
                GoalBurst(color: accent)
                    .id(burstToken)
                    .allowsHitTesting(false)
            }
        }
        .onChange(of: isAtGoal) { _, met in
            if met && !wasAtGoal {
                burstToken += 1
                Haptics.success()
            }
            wasAtGoal = met
        }
    }

    private var isAtGoal: Bool {
        switch state {
        case .inProgress: false
        case .atGoal, .overload: true
        }
    }

    private var fillAmount: Double {
        switch state {
        case .inProgress(_, _, let progress): progress
        case .atGoal, .overload: 1.0
        }
    }

    private var glowColor: Color {
        switch state {
        case .inProgress: Theme.Glow.inProgressColor
        case .atGoal:     Theme.Glow.atGoalColor
        case .overload:   Theme.Glow.overloadColor
        }
    }

    @ViewBuilder
    private var centerContent: some View {
        switch state {
        case .inProgress(let count, let goal, _):
            VStack(spacing: 4) {
                Text("\(count)")
                    .font(Theme.FontScale.counter())
                    .foregroundColor(Theme.textPrimary)
                    .contentTransition(.numericText())
                Text("of \(goal)")
                    .font(Theme.FontScale.secondary())
                    .foregroundColor(Theme.textSecondary)
            }
        case .atGoal(let goal):
            VStack(spacing: 4) {
                Text("★")
                    .font(Theme.FontScale.goalStar())
                    .foregroundColor(accent)
                Text("\(goal) DONE")
                    .font(Theme.FontScale.micro())
                    .tracking(0.8)
                    .foregroundColor(accent)
            }
        case .overload(let count, _, let extra):
            VStack(spacing: 4) {
                Text("+\(extra)")
                    .font(Theme.FontScale.counterOverload())
                    .foregroundColor(accent)
                    .contentTransition(.numericText())
                Text("\(count) TOTAL")
                    .font(Theme.FontScale.micro())
                    .tracking(0.8)
                    .foregroundColor(accent)
            }
        }
    }
}

/// One-shot celebration that plays when the ring crosses into its goal state:
/// an expanding ring "ping" plus a burst of spokes radiating outward. Re-mounts
/// (and replays) whenever its `.id` changes in the parent.
private struct GoalBurst: View {
    let color: Color
    @State private var animate = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(color, lineWidth: 3)
                .frame(width: 240, height: 240)
                .scaleEffect(animate ? 1.3 : 0.92)
                .opacity(animate ? 0 : 0.7)

            ForEach(0..<10, id: \.self) { i in
                Capsule()
                    .fill(color)
                    .frame(width: 4, height: 16)
                    .offset(y: animate ? -154 : -116)
                    .opacity(animate ? 0 : 0.9)
                    .rotationEffect(.degrees(Double(i) / 10 * 360))
            }
        }
        .onAppear {
            animate = false
            withAnimation(.easeOut(duration: 0.85)) { animate = true }
        }
    }
}

private extension RingState {
    /// Identity for SwiftUI transitions. Within a `.kind`, child Text views
    /// crossfade via `.contentTransition(.numericText())`; across `.kind`s,
    /// the `.id` change causes a full re-mount and triggers the scale/opacity
    /// transition on `centerContent`.
    var kind: String {
        switch self {
        case .inProgress: "inProgress"
        case .atGoal:     "atGoal"
        case .overload:   "overload"
        }
    }
}

#Preview("In progress") {
    ProgressRingView(state: .inProgress(count: 7, goal: 10, progress: 0.7))
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bgGradient)
        .preferredColorScheme(.dark)
}

#Preview("At goal") {
    ProgressRingView(state: .atGoal(goal: 10))
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bgGradient)
        .preferredColorScheme(.dark)
}

#Preview("Overload") {
    ProgressRingView(state: .overload(count: 12, goal: 10, extra: 2))
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bgGradient)
        .preferredColorScheme(.dark)
}
