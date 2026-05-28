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

/// A breathing dot for inline / button-overlay use where a skeleton would be
/// overkill (save buttons, single-element mutations). Picks up the tier and
/// shifts to the lavender→amber gradient at `.extended`.
struct LoadingPulse: View {
    var size: CGFloat = 10
    @Environment(\.loadingTier) private var tier
    @State private var scale: CGFloat = 0.7
    @State private var glow: CGFloat = 0.0

    var body: some View {
        ZStack {
            Circle()
                .fill(tier == .extended ? Theme.accentGradient : LinearGradient(
                    colors: [Theme.accentLavender, Theme.accentLavender],
                    startPoint: .top, endPoint: .bottom
                ))
                .frame(width: size * 2.2, height: size * 2.2)
                .blur(radius: size * 0.6)
                .opacity(glow)
            Circle()
                .fill(tier == .extended ? Theme.accentAmber : Theme.accentLavender)
                .frame(width: size, height: size)
                .scaleEffect(scale)
        }
        .frame(width: size * 2.2, height: size * 2.2)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                scale = 1.0
                glow = 0.55
            }
        }
    }
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

/// Small dimmed overlay with a `LoadingPulse` — for save/mutation flows where
/// the user just tapped a button. Same 2-tier delay band: nothing below 250 ms,
/// pulse between 250 ms and 1.5 s, with a hint label past 1.5 s.
struct WorkingOverlay: View {
    let isWorking: Bool
    var hint: String = "saving…"

    @State private var phase: LoadingTier = .hidden

    var body: some View {
        ZStack {
            if isWorking && phase != .hidden {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .transition(.opacity)
                VStack(spacing: Theme.Spacing.md) {
                    LoadingPulse(size: 14)
                        .environment(\.loadingTier, phase)
                    if phase == .extended {
                        Text(hint)
                            .font(Theme.FontScale.secondary())
                            .foregroundColor(Theme.textSecondary)
                            .transition(.opacity)
                    }
                }
                .padding(Theme.Spacing.lg)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .fill(Theme.surface)
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
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
