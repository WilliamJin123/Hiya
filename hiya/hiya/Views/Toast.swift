import SwiftUI

/// Lightweight top-of-screen toast for background-task feedback (e.g. the
/// dismiss-first LogSheet save). Auto-dismisses on its own; never blocks taps
/// on the underlying view. Success toasts fade fast, failure toasts linger so
/// the user can read the reason.
struct ToastItem: Identifiable, Equatable, Sendable {
    enum Kind: Sendable { case success, failure }
    let id = UUID()
    let kind: Kind
    let message: String

    static func success(_ message: String) -> ToastItem {
        ToastItem(kind: .success, message: message)
    }

    static func failure(_ message: String) -> ToastItem {
        ToastItem(kind: .failure, message: message)
    }
}

/// Drop this near the top of a ZStack and bind it to a `@State var toast: ToastItem?`.
/// Setting the binding to a new item shows the toast; it auto-clears the binding
/// after its lifetime (1.6 s for success, 3.6 s for failure so the reason can be read).
struct ToastOverlay: View {
    @Binding var item: ToastItem?

    var body: some View {
        VStack(spacing: 0) {
            if let item {
                pill(for: item)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: item.id) {
                        let lifetime: Double = item.kind == .success ? 1.6 : 3.6
                        try? await Task.sleep(for: .seconds(lifetime))
                        guard !Task.isCancelled else { return }
                        withAnimation(.easeInOut(duration: 0.28)) { self.item = nil }
                    }
            }
            Spacer()
        }
        .padding(.top, Theme.Spacing.sm)
        .padding(.horizontal, Theme.Spacing.md)
        .animation(.easeInOut(duration: 0.28), value: item?.id)
        // Failure toasts swallow taps so users can long-press / read them
        // without accidentally tapping through; success toasts stay out of the way.
        .allowsHitTesting(item?.kind == .failure)
    }

    @ViewBuilder
    private func pill(for item: ToastItem) -> some View {
        let tint = color(for: item.kind)
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: icon(for: item.kind))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(tint)
            Text(item.message)
                .font(Theme.FontScale.secondary())
                .foregroundColor(Theme.textPrimary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm + 2)
        .background(Capsule().fill(Theme.surface.opacity(0.96)))
        .overlay(Capsule().stroke(tint.opacity(0.45), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 14, x: 0, y: 6)
    }

    private func icon(for kind: ToastItem.Kind) -> String {
        switch kind {
        case .success: "checkmark.circle.fill"
        case .failure: "exclamationmark.triangle.fill"
        }
    }

    private func color(for kind: ToastItem.Kind) -> Color {
        switch kind {
        case .success: Theme.valencePositive
        case .failure: Theme.valenceNegative
        }
    }
}

#Preview("Success") {
    StatefulPreview(initial: ToastItem.success("Saved")) { binding in
        ZStack {
            Theme.bgGradient.ignoresSafeArea()
            ToastOverlay(item: binding)
        }
    }
}

#Preview("Failure") {
    StatefulPreview(initial: ToastItem.failure("Couldn't save — network unavailable.")) { binding in
        ZStack {
            Theme.bgGradient.ignoresSafeArea()
            ToastOverlay(item: binding)
        }
    }
}

/// Tiny preview-only helper so the previews above can render with a binding.
private struct StatefulPreview<Content: View>: View {
    @State private var value: ToastItem?
    let content: (Binding<ToastItem?>) -> Content

    init(initial: ToastItem?, @ViewBuilder content: @escaping (Binding<ToastItem?>) -> Content) {
        _value = State(initialValue: initial)
        self.content = content
    }

    var body: some View { content($value) }
}
