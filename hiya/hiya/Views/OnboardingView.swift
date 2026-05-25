import SwiftUI

struct OnboardingView: View {
    let repo: HiyaRepository
    let session: SessionViewModel
    @State private var vm: OnboardingViewModel

    init(repo: HiyaRepository, session: SessionViewModel) {
        self.repo = repo
        self.session = session
        _vm = State(initialValue: OnboardingViewModel(repo: repo, profile: session.profile))
    }

    var body: some View {
        ZStack {
            Theme.bgGradient.ignoresSafeArea()
            VStack(spacing: 0) {
                TabView(selection: $vm.page) {
                    WelcomeCard().tag(0)
                    TwoKindsCard().tag(1)
                    HowToLogCard().tag(2)
                    SetGoalsCard(coldGoal: $vm.coldGoal, warmGoal: $vm.warmGoal).tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.25), value: vm.page)

                if let error = vm.errorMessage {
                    Text(error)
                        .font(Theme.FontScale.secondary())
                        .foregroundColor(Theme.valenceNegative)
                        .padding(.horizontal, Theme.Spacing.md)
                }
                pageDots
                actionButton
            }
            .padding(.bottom, Theme.Spacing.xl)
        }
        .preferredColorScheme(.dark)
    }

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<OnboardingViewModel.pageCount, id: \.self) { i in
                Circle()
                    .fill(i == vm.page ? Theme.accentLavender : Theme.ringTrack)
                    .frame(width: 7, height: 7)
            }
        }
        .padding(.bottom, Theme.Spacing.lg)
    }

    private var actionButton: some View {
        Button {
            if vm.isLastPage {
                Task {
                    if await vm.finish() { session.completeOnboarding() }
                }
            } else {
                withAnimation { vm.next() }
            }
        } label: {
            Text(vm.isLastPage ? "Get started" : "Continue")
                .font(Theme.FontScale.body().weight(.semibold))
                .foregroundColor(Theme.textOnAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Theme.accentLavender)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                .shadow(color: Theme.accentLavender.opacity(0.3), radius: 14, x: 0, y: 8)
        }
        .buttonStyle(.plain)
        .disabled(vm.isSaving)
        .padding(.horizontal, Theme.Spacing.md)
    }
}

// MARK: - Cards

private struct WelcomeCard: View {
    @State private var appeared = false
    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Spacer()
            Text("Hiya")
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.accentGradient)
                .scaleEffect(appeared ? 1 : 0.6)
                .opacity(appeared ? 1 : 0)
            Text("A daily nudge to talk to people.")
                .font(Theme.FontScale.body())
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 16)
            Spacer()
        }
        .padding(Theme.Spacing.xl)
        .onAppear {
            appeared = false
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) { appeared = true }
        }
    }
}

private struct TwoKindsCard: View {
    @State private var fill = false
    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()
            HStack(spacing: Theme.Spacing.lg) {
                miniRing(Theme.accentGradient, "Approaches", "New people", delay: 0)
                miniRing(Theme.accentGradientReversed, "Catch-ups", "People you know", delay: 0.18)
            }
            Text("Two kinds of conversation, kept separate: meet new people, and stay close to the ones you know.")
                .font(Theme.FontScale.body())
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(Theme.Spacing.xl)
        .onAppear {
            fill = false
            withAnimation(.easeOut(duration: 0.9)) { fill = true }
        }
    }

    private func miniRing(_ gradient: LinearGradient, _ label: String, _ sub: String, delay: Double) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            ZStack {
                Circle().stroke(Theme.ringTrack, lineWidth: 10)
                Circle()
                    .trim(from: 0, to: fill ? 0.8 : 0)
                    .stroke(gradient, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.9).delay(delay), value: fill)
            }
            .frame(width: 96, height: 96)
            Text(label).font(Theme.FontScale.body()).foregroundColor(Theme.textPrimary)
            Text(sub).font(Theme.FontScale.secondary()).foregroundColor(Theme.textSecondary)
        }
    }
}

private struct HowToLogCard: View {
    @State private var appeared = false
    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()
            Text("Log it in a tap")
                .font(Theme.FontScale.title())
                .foregroundColor(Theme.textPrimary)

            HStack(spacing: Theme.Spacing.md) {
                Circle().fill(Theme.valencePositive).frame(width: 9, height: 9)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Maya").font(Theme.FontScale.body()).foregroundColor(Theme.textPrimary)
                    Text("complimented her bag at the cafe")
                        .font(Theme.FontScale.secondary()).foregroundColor(Theme.textSecondary)
                }
                Spacer()
            }
            .padding(Theme.Spacing.md)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            .opacity(appeared ? 1 : 0)
            .offset(x: appeared ? 0 : -30)

            HStack(spacing: Theme.Spacing.sm) {
                chip("Good", Theme.valencePositive)
                chip("OK", Theme.valenceNeutral)
                chip("Rough", Theme.valenceNegative)
            }
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.8)

            Text("Every chat counts — even the rough ones. Rate it and move on.")
                .font(Theme.FontScale.body())
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(Theme.Spacing.xl)
        .onAppear {
            appeared = false
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1)) { appeared = true }
        }
    }

    private func chip(_ title: String, _ color: Color) -> some View {
        Text(title)
            .font(Theme.FontScale.secondary())
            .foregroundColor(Theme.textOnAccent)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(color))
    }
}

private struct SetGoalsCard: View {
    @Binding var coldGoal: Int
    @Binding var warmGoal: Int
    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()
            Text("Set your daily goals")
                .font(Theme.FontScale.title())
                .foregroundColor(Theme.textPrimary)
            Text("How many a day feels right? Change these anytime in Settings.")
                .font(Theme.FontScale.secondary())
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
            goalStepper("Approaches", "New people", $coldGoal, Theme.coldAccent)
            goalStepper("Catch-ups", "People you know", $warmGoal, Theme.warmAccent)
            Spacer()
        }
        .padding(Theme.Spacing.xl)
    }

    private func goalStepper(_ title: String, _ sub: String, _ value: Binding<Int>, _ accent: Color) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.FontScale.body()).foregroundColor(Theme.textPrimary)
                Text(sub).font(Theme.FontScale.secondary()).foregroundColor(Theme.textSecondary)
            }
            Spacer()
            Text("\(value.wrappedValue)")
                .font(.custom(Theme.FontName.counterMono, size: 22).weight(.semibold))
                .foregroundColor(accent)
                .frame(minWidth: 32, alignment: .trailing)
                .contentTransition(.numericText())
            Stepper("", value: value, in: 1...50).labelsHidden().fixedSize()
        }
        .padding(Theme.Spacing.md)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }
}

#Preview {
    OnboardingView(repo: MockHiyaRepository(), session: SessionViewModel(repo: MockHiyaRepository()))
}
