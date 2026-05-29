import SwiftUI

struct AppGateView: View {
    let repo: HiyaRepository
    @State private var session: SessionViewModel
    @State private var notifications: NotificationManager
    @Environment(\.scenePhase) private var scenePhase

    init(repo: HiyaRepository) {
        self.repo = repo
        _session = State(initialValue: SessionViewModel(repo: repo))
        _notifications = State(initialValue: NotificationManager(scheduler: LiveNotificationScheduler()))
    }

    var body: some View {
        Group {
            switch session.state {
            case .loading:
                ZStack {
                    Theme.bgGradient.ignoresSafeArea()
                    LoadingOrb(size: 44, lineWidth: 4)
                }
                .transition(.opacity)
                // Soft ambient bed fades in under the splash and fades out
                // the moment the session resolves. No-op if sounds are off.
                .onAppear { SoundEngine.shared.startAmbience() }
                .onDisappear { SoundEngine.shared.stopAmbience() }
            case .app:
                RootView(repo: repo)
                    .environment(session)
                    .environment(notifications)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            case .onboarding:
                OnboardingView(repo: repo, session: session)
                    .transition(.opacity)
            case .auth:
                AuthView(session: session)
                    .transition(.opacity)
            }
        }
        // Smooths the very first thing the user sees: loading → app fades
        // instead of hard-cutting once the cached session hydrates.
        .animation(.easeInOut(duration: 0.32), value: session.state)
        .task {
            if session.state == .loading { await session.start() }
        }
        .task { await notifications.refreshAuthorizationStatus() }
        // Engine is idempotent — first call wires the audio graph + pre-renders
        // every effect buffer; later calls no-op.
        .task { SoundEngine.shared.start() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await notifications.refreshAuthorizationStatus() }
            }
        }
    }
}

#Preview {
    AppGateView(repo: MockHiyaRepository())
}
