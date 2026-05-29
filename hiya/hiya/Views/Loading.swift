import SwiftUI

/// Two-tier delay band for loading UI. Below 250 ms we render nothing — fast
/// network round-trips don't flash a skeleton. Between 250 ms and 1.5 s we
/// show the "typical" shimmer (cool lavender, ~1.6 s sweep). Past 1.5 s we
/// shift into "extended": the gradient leans into amber and the sweep slows,
/// communicating "I'm still here, this is taking a moment" without an error.
enum LoadingTier: Equatable, Sendable {
    case hidden
    case typical
    case extended

    /// Sweep period (seconds) for the shimmer highlight at this tier. Slower
    /// at .extended on purpose — the calmer cadence reads as patience, not stuck.
    var shimmerPeriod: Double {
        switch self {
        case .hidden, .typical: return 1.6
        case .extended:         return 2.4
        }
    }

    static let typicalThresholdMs = 250
    static let extendedThresholdMs = 1500

    /// Pure timing helper — keeps the threshold logic testable without spinning
    /// up SwiftUI / sleeping in tests.
    static func tier(forElapsedMs ms: Int) -> LoadingTier {
        if ms < typicalThresholdMs { return .hidden }
        if ms < extendedThresholdMs { return .typical }
        return .extended
    }
}

// MARK: - Environment plumbing

private struct LoadingTierKey: EnvironmentKey {
    static let defaultValue: LoadingTier = .typical
}

extension EnvironmentValues {
    /// The current delay-band tier, propagated from `DelayedLoadingModifier`
    /// down into skeleton components so they can adjust intensity.
    var loadingTier: LoadingTier {
        get { self[LoadingTierKey.self] }
        set { self[LoadingTierKey.self] = newValue }
    }
}

// MARK: - Primitives

/// A rounded-rect placeholder with a soft highlight that sweeps left → right.
/// Compose multiple of these to mock up the shape of the data about to load.
/// Picks up the active tier from `\.loadingTier` and intensifies at `.extended`.
struct SkeletonView: View {
    var cornerRadius: CGFloat = Theme.Radius.sm
    @Environment(\.loadingTier) private var tier
    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Theme.surface)
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(
                        LinearGradient(
                            stops: highlightStops,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * 1.5)
                    .offset(x: geo.size.width * phase)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .onAppear { startAnimating() }
            .onChange(of: tier) { _, _ in startAnimating() }
        }
    }

    private func startAnimating() {
        phase = -1
        withAnimation(.linear(duration: tier.shimmerPeriod).repeatForever(autoreverses: false)) {
            phase = 1.5
        }
    }

    private var highlightStops: [Gradient.Stop] {
        let color: Color = tier == .extended
            ? Theme.accentAmber.opacity(0.22)
            : Theme.accentLavender.opacity(0.18)
        return [
            .init(color: .clear, location: 0),
            .init(color: color, location: 0.5),
            .init(color: .clear, location: 1),
        ]
    }
}

/// A small spinning gradient ring — a miniature of the home `ProgressRingView`.
/// Used wherever a heavier skeleton would be overkill (auth, account save,
/// the AppGate splash). Picks up the tier and shifts the gradient + cadence
/// at `.extended`: amber-leading sweep and a calmer rotation.
struct LoadingOrb: View {
    var size: CGFloat = 32
    var lineWidth: CGFloat = 3.5
    @Environment(\.loadingTier) private var tier
    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.ringTrack, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: 0.72)
                .stroke(
                    tier == .extended ? Theme.accentGradientReversed : Theme.accentGradient,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(rotation))
        }
        .frame(width: size, height: size)
        .shadow(
            color: (tier == .extended ? Theme.accentAmber : Theme.accentLavender).opacity(0.35),
            radius: size * 0.25
        )
        .onAppear { startSpinning() }
        .onChange(of: tier) { _, _ in startSpinning() }
    }

    private func startSpinning() {
        // Restart from 0 so the new cadence takes effect cleanly when the tier
        // changes (otherwise SwiftUI would keep the prior animation's velocity).
        rotation = 0
        let period: Double = tier == .extended ? 1.8 : 1.1
        withAnimation(.linear(duration: period).repeatForever(autoreverses: false)) {
            rotation = 360
        }
    }
}

/// Back-compat shim — kept as a typealias-style wrapper because earlier code
/// used `LoadingPulse`. New code should call `LoadingOrb` directly.
struct LoadingPulse: View {
    var size: CGFloat = 10
    var body: some View { LoadingOrb(size: size * 2.4, lineWidth: max(2, size * 0.32)) }
}

// MARK: - Delay-band wrapper

/// Renders `placeholder` (with the 2-tier shimmer) while loading the *first*
/// time. Once `hasLoaded` flips true, the content stays put across subsequent
/// refreshes — that's the stale-while-revalidate seam. Below 250 ms of waiting
/// we render nothing (prevents flash on fast networks).
private struct DelayedLoadingModifier<Placeholder: View>: ViewModifier {
    let isLoading: Bool
    let hasLoaded: Bool
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var phase: LoadingTier = .hidden

    private var showsPlaceholder: Bool { isLoading && !hasLoaded }

    func body(content: Content) -> some View {
        Group {
            if hasLoaded {
                content
                    // Even when the network was instant (< 250 ms, no skeleton
                    // shown), content blooms in instead of popping — a small
                    // fade + scale that reads as "the data settled into place."
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            } else if showsPlaceholder && phase != .hidden {
                placeholder()
                    .environment(\.loadingTier, phase)
                    .transition(.opacity)
            } else {
                Color.clear
            }
        }
        .animation(.easeInOut(duration: 0.22), value: phase)
        .animation(.easeOut(duration: 0.32), value: hasLoaded)
        .task(id: showsPlaceholder) {
            phase = .hidden
            guard showsPlaceholder else { return }
            try? await Task.sleep(for: .milliseconds(LoadingTier.typicalThresholdMs))
            guard !Task.isCancelled else { return }
            phase = .typical
            try? await Task.sleep(
                for: .milliseconds(LoadingTier.extendedThresholdMs - LoadingTier.typicalThresholdMs)
            )
            guard !Task.isCancelled else { return }
            phase = .extended
        }
    }
}

extension View {
    /// Show `placeholder` while the view is loading for the first time. Uses
    /// a two-tier delay band: nothing below 250 ms (no flash), shimmer between
    /// 250 ms and 1.5 s, intensified shimmer past 1.5 s. Once `hasLoaded`
    /// flips true, the placeholder never re-appears — refreshes are silent.
    func delayedLoading<Placeholder: View>(
        isLoading: Bool,
        hasLoaded: Bool,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) -> some View {
        modifier(DelayedLoadingModifier(
            isLoading: isLoading,
            hasLoaded: hasLoaded,
            placeholder: placeholder
        ))
    }
}

// MARK: - Working overlay (writes)

/// Non-blocking in-flight indicator. A small `LoadingOrb` floats in the
/// top-trailing corner while a save / mutation is running, so the user can keep
/// typing or dismiss the sheet — no dimmed modal, no "frozen" feel. Same 2-tier
/// delay band as `delayedLoading`: nothing below 250 ms, orb between 250 ms and
/// 1.5 s, with a hint label appearing past 1.5 s.
struct WorkingOverlay: View {
    let isWorking: Bool
    var hint: String = "saving…"

    @State private var phase: LoadingTier = .hidden

    var body: some View {
        VStack {
            HStack {
                Spacer()
                if isWorking && phase != .hidden {
                    HStack(spacing: Theme.Spacing.sm) {
                        LoadingOrb(size: 22, lineWidth: 2.5)
                            .environment(\.loadingTier, phase)
                        if phase == .extended {
                            Text(hint)
                                .font(Theme.FontScale.micro())
                                .tracking(0.6)
                                .foregroundColor(Theme.textSecondary)
                                .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.sm + 2)
                    .padding(.vertical, Theme.Spacing.xs + 2)
                    .background(
                        Capsule().fill(Theme.surface.opacity(0.92))
                    )
                    .overlay(
                        Capsule().stroke(Theme.divider, lineWidth: 1)
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .topTrailing)))
                }
            }
            Spacer()
        }
        .padding(.top, Theme.Spacing.sm)
        .padding(.trailing, Theme.Spacing.md)
        .allowsHitTesting(false) // never block taps on the underlying form
        .animation(.easeInOut(duration: 0.22), value: phase)
        .animation(.easeInOut(duration: 0.22), value: isWorking)
        .task(id: isWorking) {
            phase = .hidden
            guard isWorking else { return }
            try? await Task.sleep(for: .milliseconds(LoadingTier.typicalThresholdMs))
            guard !Task.isCancelled else { return }
            phase = .typical
            try? await Task.sleep(
                for: .milliseconds(LoadingTier.extendedThresholdMs - LoadingTier.typicalThresholdMs)
            )
            guard !Task.isCancelled else { return }
            phase = .extended
        }
    }
}
