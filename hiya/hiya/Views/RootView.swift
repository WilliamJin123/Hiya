import SwiftUI

struct RootView: View {
    let repo: HiyaRepository

    var body: some View {
        TabView {
            // HomeView owns its own NavigationStack (toolbar + sheets), so it's
            // not wrapped here. People/History/Insights rely on a parent stack.
            HomeView(repo: repo)
                .tabItem { Label("Home", systemImage: "circle.dashed") }
            NavigationStack { PeopleView(repo: repo) }
                .tabItem { Label("People", systemImage: "person.2.fill") }
            NavigationStack { HistoryView(repo: repo) }
                .tabItem { Label("History", systemImage: "calendar") }
            NavigationStack { InsightsView(repo: repo) }
                .tabItem { Label("Insights", systemImage: "chart.bar.fill") }
        }
        .tint(Theme.accentLavender)
    }
}

#Preview {
    RootView(repo: MockHiyaRepository())
        .preferredColorScheme(.dark)
}
