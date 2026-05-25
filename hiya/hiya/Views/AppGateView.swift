import SwiftUI

struct AppGateView: View {
    let repo: HiyaRepository
    @State private var session: SessionViewModel

    init(repo: HiyaRepository) {
        self.repo = repo
        _session = State(initialValue: SessionViewModel(repo: repo))
    }

    var body: some View {
        Group {
            switch session.state {
            case .loading:
                ZStack {
                    Theme.bgGradient.ignoresSafeArea()
                    ProgressView().tint(Theme.accentLavender)
                }
            case .app:
                RootView(repo: repo)
                    .environment(session)
            case .onboarding:
                ZStack { Theme.bgGradient.ignoresSafeArea(); ProgressView().tint(Theme.accentLavender) }
            case .auth:
                AuthView(session: session)
            }
        }
        .task {
            if session.state == .loading { await session.start() }
        }
    }
}

#Preview {
    AppGateView(repo: MockHiyaRepository())
}
