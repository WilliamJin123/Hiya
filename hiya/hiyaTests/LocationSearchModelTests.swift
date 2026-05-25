import Testing
@testable import hiya

struct LocationSearchModelTests {
    @Test func displayString_joinsTitleAndSubtitle() {
        #expect(LocationSuggestion(title: "Blue Bottle", subtitle: "1 Main St").displayString == "Blue Bottle, 1 Main St")
    }
    @Test func displayString_titleOnlyWhenNoSubtitle() {
        #expect(LocationSuggestion(title: "Blue Bottle", subtitle: "").displayString == "Blue Bottle")
    }
}
