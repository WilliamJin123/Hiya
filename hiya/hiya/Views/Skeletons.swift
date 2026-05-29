import SwiftUI

// Per-screen skeleton compositions, used by `delayedLoading(...)` on each
// screen's content. Each one mirrors the actual layout of the loaded view —
// so the user perceives "shape forming → content arriving" instead of a flat
// spinner. The shimmer intensity adapts to `\.loadingTier` via SkeletonView.

// MARK: - Home

/// Mirrors the cold/warm page layout: ring placeholder, streak line, log
/// button placeholder, and a few log rows. The ring is a hollow stroked circle
/// — it reads as "ring loading" even before content lands.
struct HomeSkeleton: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            ringPlaceholder
            streakPlaceholder
            logButtonPlaceholder
            sectionHeaderPlaceholder
            VStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { i in
                    SkeletonLogRow()
                    if i < 2 { Theme.divider.frame(height: 1) }
                }
            }
        }
        .padding(.top, Theme.Spacing.lg)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.xl)
    }

    private var ringPlaceholder: some View {
        Circle()
            .stroke(Theme.ringTrack, lineWidth: 18)
            .frame(width: 240, height: 240)
            .overlay {
                // Inner shimmer disc to give the ring some life while empty.
                Circle()
                    .fill(Theme.surface.opacity(0.6))
                    .frame(width: 200, height: 200)
                    .overlay(
                        SkeletonView(cornerRadius: 100)
                            .frame(width: 110, height: 24)
                    )
            }
    }

    private var streakPlaceholder: some View {
        HStack(spacing: Theme.Spacing.sm) {
            SkeletonView(cornerRadius: 4).frame(width: 18, height: 18)
            SkeletonView(cornerRadius: 4).frame(width: 40, height: 28)
            SkeletonView(cornerRadius: 4).frame(width: 140, height: 12)
        }
    }

    private var logButtonPlaceholder: some View {
        SkeletonView(cornerRadius: 22)
            .frame(width: 100, height: 44)
    }

    private var sectionHeaderPlaceholder: some View {
        HStack {
            SkeletonView(cornerRadius: 4).frame(width: 60, height: 12)
            Spacer()
        }
    }
}

/// One log-list row placeholder: dot + two text bars.
struct SkeletonLogRow: View {
    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Circle().fill(Theme.surface).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 6) {
                SkeletonView(cornerRadius: 4).frame(width: 120, height: 14)
                SkeletonView(cornerRadius: 4).frame(width: 200, height: 11)
            }
            Spacer()
            SkeletonView(cornerRadius: 4).frame(width: 36, height: 10)
        }
        .padding(.vertical, 10)
    }
}

// MARK: - People

/// Rows of name + activity strip placeholder.
struct PeopleSkeleton: View {
    var body: some View {
        VStack(spacing: 0) {
            sectionHeader
            ForEach(0..<5, id: \.self) { i in
                SkeletonPersonRow()
                if i < 4 { Theme.divider.frame(height: 1) }
            }
        }
        .padding(.top, Theme.Spacing.md)
        .padding(.horizontal, Theme.Spacing.md)
    }

    private var sectionHeader: some View {
        HStack {
            SkeletonView(cornerRadius: 4).frame(width: 80, height: 12)
            Spacer()
        }
        .padding(.bottom, Theme.Spacing.sm)
    }
}

private struct SkeletonPersonRow: View {
    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 8) {
                SkeletonView(cornerRadius: 4).frame(width: 110, height: 14)
                // 14-day activity strip.
                HStack(spacing: 3) {
                    ForEach(0..<14, id: \.self) { _ in
                        SkeletonView(cornerRadius: 2).frame(width: 9, height: 16)
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 12)
    }
}

// MARK: - History

/// Day-grouped log rows.
struct HistorySkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            ForEach(0..<3, id: \.self) { d in
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        SkeletonView(cornerRadius: 4).frame(width: 100, height: 12)
                        Spacer()
                        SkeletonView(cornerRadius: 4).frame(width: 50, height: 10)
                    }
                    .padding(.bottom, Theme.Spacing.sm)
                    ForEach(0..<2, id: \.self) { i in
                        SkeletonLogRow()
                        if i < 1 { Theme.divider.frame(height: 1) }
                    }
                }
                if d < 2 { Theme.divider.frame(height: 1) }
            }
        }
        .padding(.top, Theme.Spacing.md)
        .padding(.horizontal, Theme.Spacing.md)
    }
}

// MARK: - Insights

/// Two stat blocks + a chart band + a row of lesson cards.
/// Insights aggregates a year of data, so it can run noticeably slower than
/// the other tabs — a centered orb above the shimmer makes "still working"
/// obvious instead of relying on the shimmer alone.
struct InsightsSkeleton: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            LoadingOrb(size: 40, lineWidth: 3.5)
                .padding(.top, Theme.Spacing.xl)
                .padding(.bottom, Theme.Spacing.sm)
            HStack(spacing: Theme.Spacing.md) {
                statCard
                statCard
            }
            chartPlaceholder
            valenceBar
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    SkeletonView(cornerRadius: 4).frame(width: 80, height: 12)
                    Spacer()
                }
                .padding(.bottom, Theme.Spacing.sm)
                ForEach(0..<2, id: \.self) { i in
                    SkeletonLogRow()
                    if i < 1 { Theme.divider.frame(height: 1) }
                }
            }
        }
        .padding(.top, Theme.Spacing.md)
        .padding(.horizontal, Theme.Spacing.md)
    }

    private var statCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SkeletonView(cornerRadius: 4).frame(width: 80, height: 11)
            SkeletonView(cornerRadius: 4).frame(width: 60, height: 28)
            SkeletonView(cornerRadius: 4).frame(width: 100, height: 10)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md).fill(Theme.surface)
        )
    }

    private var chartPlaceholder: some View {
        SkeletonView(cornerRadius: Theme.Radius.md)
            .frame(height: 140)
    }

    private var valenceBar: some View {
        SkeletonView(cornerRadius: 6)
            .frame(height: 22)
    }
}

// MARK: - Challenges

/// Active section header + 3 challenge rows.
struct ChallengesSkeleton: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                SkeletonView(cornerRadius: 4).frame(width: 70, height: 12)
                Spacer()
            }
            .padding(.bottom, Theme.Spacing.sm)
            ForEach(0..<3, id: \.self) { i in
                SkeletonChallengeRow()
                if i < 2 { Theme.divider.frame(height: 1) }
            }
        }
        .padding(.top, Theme.Spacing.md)
        .padding(.horizontal, Theme.Spacing.md)
    }
}

private struct SkeletonChallengeRow: View {
    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            SkeletonView(cornerRadius: 4).frame(width: 14, height: 14)
            VStack(alignment: .leading, spacing: 6) {
                SkeletonView(cornerRadius: 4).frame(width: 140, height: 14)
                SkeletonView(cornerRadius: 4).frame(width: 220, height: 11)
            }
            Spacer()
            SkeletonView(cornerRadius: 4).frame(width: 32, height: 11)
        }
        .padding(.vertical, 12)
    }
}
