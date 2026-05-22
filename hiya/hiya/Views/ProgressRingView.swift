import SwiftUI

struct ProgressRingView: View {
    let state: RingState

    var body: some View {
        ZStack {
            Circle().stroke(Theme.ringTrack, lineWidth: 18)

            Circle()
                .trim(from: 0, to: fillAmount)
                .stroke(Theme.accentGradient, style: StrokeStyle(lineWidth: 18, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.4), value: fillAmount)

            centerContent
                .id(state.kind)
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
                .animation(.spring(response: 0.45, dampingFraction: 0.7), value: state.kind)
        }
        .frame(width: 240, height: 240)
        .shadow(color: glowColor, radius: Theme.Glow.blur, x: 0, y: 0)
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
                    .foregroundColor(Theme.accentAmber)
                Text("\(goal) DONE")
                    .font(Theme.FontScale.micro())
                    .tracking(0.8)
                    .foregroundColor(Theme.accentAmber)
            }
        case .overload(let count, _, let extra):
            VStack(spacing: 4) {
                Text("+\(extra)")
                    .font(Theme.FontScale.counterOverload())
                    .foregroundColor(Theme.accentAmber)
                    .contentTransition(.numericText())
                Text("\(count) TOTAL")
                    .font(Theme.FontScale.micro())
                    .tracking(0.8)
                    .foregroundColor(Theme.accentAmber)
            }
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
