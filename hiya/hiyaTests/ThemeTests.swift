import Testing
import SwiftUI
@testable import hiya

struct ThemeTests {
    @Test func accent_coldIsLavender_warmIsAmber() {
        #expect(Theme.accent(for: .cold) == Theme.accentLavender)
        #expect(Theme.accent(for: .warm) == Theme.accentAmber)
        #expect(Theme.coldAccent == Theme.accentLavender)
        #expect(Theme.warmAccent == Theme.accentAmber)
    }
}
