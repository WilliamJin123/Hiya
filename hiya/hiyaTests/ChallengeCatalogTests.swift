import Testing
import Foundation
@testable import hiya

struct ChallengeCatalogTests {
    @Test func catalog_isNonEmpty_withUniqueSlugs() {
        let slugs = ChallengeTemplate.catalog.map(\.slug)
        #expect(!slugs.isEmpty)
        #expect(Set(slugs).count == slugs.count, "slugs must be unique")
    }

    @Test func draft_fromTemplate_carriesCatalogSource() {
        let t = ChallengeTemplate.catalog[0]
        let draft = ChallengeDraft(template: t)
        #expect(draft.source == .catalog)
        #expect(draft.templateSlug == t.slug)
        #expect(draft.track == t.track)
    }
}
