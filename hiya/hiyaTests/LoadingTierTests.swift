import Testing
@testable import hiya

/// Locks in the delay-band thresholds. The actual animation uses these
/// constants via `Task.sleep`, so the band edges should match what users see.
struct LoadingTierTests {

    @Test func tier_hidden_atZero() {
        #expect(LoadingTier.tier(forElapsedMs: 0) == .hidden)
    }

    @Test func tier_hidden_justBelowTypical() {
        #expect(LoadingTier.tier(forElapsedMs: 249) == .hidden)
    }

    @Test func tier_typical_atTypicalThreshold() {
        #expect(LoadingTier.tier(forElapsedMs: 250) == .typical)
    }

    @Test func tier_typical_justBelowExtended() {
        #expect(LoadingTier.tier(forElapsedMs: 1499) == .typical)
    }

    @Test func tier_extended_atExtendedThreshold() {
        #expect(LoadingTier.tier(forElapsedMs: 1500) == .extended)
    }

    @Test func tier_extended_wellPast() {
        #expect(LoadingTier.tier(forElapsedMs: 10_000) == .extended)
    }

    /// Extended sweep should be slower than typical — calmer cadence at long wait.
    @Test func extendedSweep_slowerThanTypical() {
        #expect(LoadingTier.extended.shimmerPeriod > LoadingTier.typical.shimmerPeriod)
    }
}
