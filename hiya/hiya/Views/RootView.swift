import SwiftUI

struct RootView: View {
    let repo: HiyaRepository

    var body: some View {
        HomeView(repo: repo)
    }
}

#Preview {
    RootView(repo: MockHiyaRepository())
}
