import SwiftUI

@main
struct hiyaApp: App {
    private let repo: HiyaRepository = LiveHiyaRepository()

    var body: some Scene {
        WindowGroup {
            AppGateView(repo: repo)
                .preferredColorScheme(.dark)
        }
    }
}
