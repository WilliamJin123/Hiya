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
                    LoadingPulse(size: 14)
                }
            case .app:
                RootView(repo: repo)
                    .environment(session)
                    .environment(notifications)
            case .onboarding:
                OnboardingView(repo: repo, session: session)
            case .auth:
                AuthView(session: session)
            }
        }
        .task {
            if session.state == .loading { await session.start() }
        }
        .task { await notifications.refreshAuthorizationStatus() }
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
