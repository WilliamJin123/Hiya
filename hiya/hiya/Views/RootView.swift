import SwiftUI

struct RootView: View {
    let repo: HiyaRepository
    /// Explicit selection so we can fire a soft `.tab` chime on change. Default
    /// matches the implicit-first-tab behaviour SwiftUI had before.
    @State private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            // HomeView owns its own NavigationStack (toolbar + sheets), so it's
            // not wrapped here. People/History/Insights rely on a parent stack.
            HomeView(repo: repo)
                .tabItem { Label("Home", systemImage: "circle.dashed") }
                .tag(0)
            NavigationStack { PeopleView(repo: repo) }
                .tabItem { Label("People", systemImage: "person.2.fill") }
                .tag(1)
            NavigationStack { HistoryView(repo: repo) }
                .tabItem { Label("History", systemImage: "calendar") }
                .tag(2)
            NavigationStack { InsightsView(repo: repo) }
                .tabItem { Label("Insights", systemImage: "chart.bar.fill") }
                .tag(3)
        }
        .tint(Theme.accentLavender)
        .onChange(of: selectedTab) { _, _ in
            SoundEngine.shared.play(.tab)
        }
    }
}

#Preview {
    RootView(repo: MockHiyaRepository())
        .environment(NotificationManager(scheduler: MockNotificationScheduler()))
        .preferredColorScheme(.dark)
}
