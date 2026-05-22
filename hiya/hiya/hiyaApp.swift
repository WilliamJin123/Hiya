import SwiftUI

@main
struct hiyaApp: App {
    private let repo: HiyaRepository = LiveHiyaRepository()

    var body: some Scene {
        WindowGroup {
            RootView(repo: repo)
        }
    }
}
