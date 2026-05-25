import Testing
import Foundation
@testable import hiya

@MainActor
struct MockHiyaRepositoryTests {

    /// Test helper: rewrite a note's immutable `createdAt` to set up ordering
    /// scenarios (PersonNote.createdAt is a `let`, like the other models).
    private func backdate(_ repo: MockHiyaRepository, noteId: UUID, days: Int) {
        guard let i = repo.personNoteRows.firstIndex(where: { $0.id == noteId }) else { return }
        let n = repo.personNoteRows[i]
        repo.personNoteRows[i] = PersonNote(
            id: n.id,
            ownerId: n.ownerId,
            personId: n.personId,
            body: n.body,
            createdAt: Calendar.current.date(byAdding: .day, value: days, to: .now)!,
            updatedAt: n.updatedAt
        )
    }

    @Test func createPerson_defaultsToCold() async throws {
        let repo = MockHiyaRepository()
        let alex = try await repo.createPerson(name: "Alex")
        #expect(alex.status == .cold)
        #expect(alex.statusChangedAt == nil)
    }

    @Test func challenges_startListCompleteAbandon() async throws {
        let repo = MockHiyaRepository()
        let draft = ChallengeDraft(title: "Test", prompt: "p", track: .cold, targetCount: 2, durationDays: 7)

        let started = try await repo.startChallenge(draft)
        var all = try await repo.challenges()
        #expect(all.count == 1)
        #expect(started.completedAt == nil)

        try await repo.completeChallenge(id: started.id)
        all = try await repo.challenges()
        #expect(all.first?.completedAt != nil)

        try await repo.abandonChallenge(id: started.id)
        all = try await repo.challenges()
        #expect(all.isEmpty)
    }

    @Test func reclassifyConversations_flipsWasColdAtTime() async throws {
        let repo = MockHiyaRepository()
        let p = try await repo.createPerson(name: "Kola")   // cold
        try await repo.logConversation(personId: p.id, valence: nil, note: nil, improvementNote: nil)
        #expect(repo.conversations.allSatisfy { $0.wasColdAtTime }, "logged cold while a cold person")

        try await repo.reclassifyConversations(personId: p.id, wasCold: false)

        #expect(repo.conversations.allSatisfy { !$0.wasColdAtTime }, "reclassified as warm")
    }

    @Test func updatePersonStatus_movesColdToWarm() async throws {
        let repo = MockHiyaRepository()
        let p = try await repo.createPerson(name: "Kola")   // defaults cold
        #expect(p.status == .cold)

        try await repo.updatePersonStatus(id: p.id, status: .warm)

        let updated = try await repo.listPeople().first { $0.id == p.id }!
        #expect(updated.status == .warm)
        #expect(updated.statusChangedAt != nil)
    }

    @Test func createPerson_storesNotes() async throws {
        let repo = MockHiyaRepository()
        let p = try await repo.createPerson(name: "Alex", status: .cold, notes: "climbing gym")
        #expect(p.notes == "climbing gym")
    }

    @Test func createPerson_withWarmStatus_setsWarmAndStampsChangedAt() async throws {
        let repo = MockHiyaRepository()
        let known = try await repo.createPerson(name: "Mentor", status: .warm)
        #expect(known.status == .warm)
        #expect(known.statusChangedAt != nil)
    }

    @Test func logConversation_honorsOccurredAt_andAdvancesLastLoggedForwardOnly() async throws {
        let repo = MockHiyaRepository()
        let p = try await repo.createPerson(name: "Alex")
        let created = repo.people.first { $0.id == p.id }!.lastLoggedAt
        let earlier = Calendar.current.date(byAdding: .day, value: -3, to: created)!

        // Back-dated log: stored occurredAt is `earlier`, but last seen must NOT regress.
        try await repo.logConversation(personId: p.id, occurredAt: earlier, valence: nil, note: nil, improvementNote: nil)
        let conv = repo.conversations.first { $0.personId == p.id }!
        #expect(abs(conv.occurredAt.timeIntervalSince(earlier)) < 0.001)
        #expect(repo.people.first { $0.id == p.id }!.lastLoggedAt == created, "back-dating must not regress last seen")

        // Forward-dated log advances last seen.
        let later = Calendar.current.date(byAdding: .day, value: 2, to: created)!
        try await repo.logConversation(personId: p.id, occurredAt: later, valence: nil, note: nil, improvementNote: nil)
        #expect(repo.people.first { $0.id == p.id }!.lastLoggedAt == later)
    }

    @Test func logConversation_onColdPerson_snapshotsCold_andLeavesStatusCold() async throws {
        let repo = MockHiyaRepository()
        let alex = try await repo.createPerson(name: "Alex")

        try await repo.logConversation(personId: alex.id, valence: nil, note: nil, improvementNote: nil)

        #expect(repo.conversations.count == 1)
        #expect(repo.conversations[0].wasColdAtTime == true)
        let updated = repo.people.first(where: { $0.id == alex.id })!
        #expect(updated.status == .cold, "cold person stays cold same-day; graduation is lazy and time-based")
    }

    @Test func logConversation_onWarmPerson_snapshotsWarm() async throws {
        let repo = MockHiyaRepository()
        // Someone you already knew (warm origin) — meetings are catch-ups, never cold.
        let alex = try await repo.createPerson(name: "Alex", status: .warm)

        try await repo.logConversation(personId: alex.id, valence: nil, note: nil, improvementNote: nil)

        #expect(repo.conversations.count == 1)
        #expect(repo.conversations[0].wasColdAtTime == false)
        let updated = repo.people.first(where: { $0.id == alex.id })!
        #expect(updated.status == .warm)
    }

    @Test func graduatePastDuePeople_promotesColdPeopleLastSeenBeforeCutoff() async throws {
        let repo = MockHiyaRepository()
        let alex = try await repo.createPerson(name: "Alex")
        // Backdate alex's last log to yesterday — they're past due for graduation.
        if let idx = repo.people.firstIndex(where: { $0.id == alex.id }) {
            repo.people[idx].lastLoggedAt = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        }

        let today = Calendar.current.startOfDay(for: .now)
        try await repo.graduatePastDuePeople(beforeLog: today)

        let updated = repo.people.first(where: { $0.id == alex.id })!
        #expect(updated.status == .warm)
        #expect(updated.statusChangedAt != nil)
    }

    @Test func graduatePastDuePeople_leavesAlone_todaysFreshPeople() async throws {
        let repo = MockHiyaRepository()
        let alex = try await repo.createPerson(name: "Alex")
        try await repo.logConversation(personId: alex.id, valence: nil, note: nil, improvementNote: nil)
        // alex.lastLoggedAt is now (today), well after start-of-today.

        let today = Calendar.current.startOfDay(for: .now)
        try await repo.graduatePastDuePeople(beforeLog: today)

        let updated = repo.people.first(where: { $0.id == alex.id })!
        #expect(updated.status == .cold, "today's freshly-met cold people don't graduate")
    }

    @Test func graduatePastDuePeople_leavesAlone_alreadyWarm() async throws {
        let repo = MockHiyaRepository()
        let alex = try await repo.createPerson(name: "Alex")
        // Make alex already warm with a stale lastLoggedAt.
        if let idx = repo.people.firstIndex(where: { $0.id == alex.id }) {
            repo.people[idx].status = .warm
            repo.people[idx].statusChangedAt = nil
            repo.people[idx].lastLoggedAt = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        }

        let today = Calendar.current.startOfDay(for: .now)
        try await repo.graduatePastDuePeople(beforeLog: today)

        let updated = repo.people.first(where: { $0.id == alex.id })!
        #expect(updated.status == .warm)
        #expect(updated.statusChangedAt == nil, "warm people are untouched, not re-stamped")
    }

    @Test func updatePersonNotes_setsAndClearsNotes() async throws {
        let repo = MockHiyaRepository()
        let alex = try await repo.createPerson(name: "Alex")

        try await repo.updatePersonNotes(id: alex.id, notes: "Met at climbing gym")
        #expect(repo.people.first(where: { $0.id == alex.id })?.notes == "Met at climbing gym")

        try await repo.updatePersonNotes(id: alex.id, notes: nil)
        #expect(repo.people.first(where: { $0.id == alex.id })?.notes == nil)
    }

    @Test func followUpSuggestions_returnsOnlyWarmPeopleNotSeenInWindow() async throws {
        let repo = MockHiyaRepository()
        // Seed three warm people with varying last-seen dates and one cold person.
        let now = Date.now
        func mk(_ name: String, status: PersonStatus, daysAgo: Int) -> Person {
            Person(
                id: UUID(),
                ownerId: repo.profile.id,
                name: name,
                status: status,
                statusChangedAt: status == .warm ? now : nil,
                createdAt: Calendar.current.date(byAdding: .day, value: -daysAgo, to: now)!,
                lastLoggedAt: Calendar.current.date(byAdding: .day, value: -daysAgo, to: now)!
            )
        }
        repo.people.append(mk("RecentWarm",    status: .warm, daysAgo: 3))   // inside window
        repo.people.append(mk("OldWarm",       status: .warm, daysAgo: 14))  // outside, oldest
        repo.people.append(mk("MidWarm",       status: .warm, daysAgo: 9))   // outside, newer
        repo.people.append(mk("StaleCold",     status: .cold, daysAgo: 30))  // wrong status

        let suggestions = try await repo.followUpSuggestions(thresholdDays: 7, limit: 3)

        #expect(suggestions.map(\.name) == ["OldWarm", "MidWarm"], "expect warm people not-seen-in-7-days, oldest first")
    }

    @Test func followUpSuggestions_respectsLimit() async throws {
        let repo = MockHiyaRepository()
        let now = Date.now
        for i in 0..<5 {
            repo.people.append(Person(
                id: UUID(),
                ownerId: repo.profile.id,
                name: "Warm\(i)",
                status: .warm,
                statusChangedAt: now,
                createdAt: now,
                lastLoggedAt: Calendar.current.date(byAdding: .day, value: -(10 + i), to: now)!
            ))
        }

        let suggestions = try await repo.followUpSuggestions(thresholdDays: 7, limit: 3)

        #expect(suggestions.count == 3)
    }

    @Test func todaysLog_propagatesWasColdAtTime() async throws {
        let repo = MockHiyaRepository()
        let alex = try await repo.createPerson(name: "Alex")
        try await repo.logConversation(personId: alex.id, valence: nil, note: nil, improvementNote: nil) // cold
        // Simulate the cycle reset: alex graduates to warm.
        if let idx = repo.people.firstIndex(where: { $0.id == alex.id }) {
            repo.people[idx].status = .warm
            repo.people[idx].statusChangedAt = .now
        }
        try await repo.logConversation(personId: alex.id, valence: nil, note: nil, improvementNote: nil) // warm

        let (start, end) = HomeViewModel.todayWindow()
        let log = try await repo.conversations(start: start, end: end)

        // log is sorted descending by occurredAt — most recent first
        #expect(log.count == 2)
        #expect(log[0].wasColdAtTime == false, "most recent log should be warm (alex graduated)")
        #expect(log[1].wasColdAtTime == true, "earlier log was cold (alex was still cold)")
    }

    @Test func addPersonNote_seedsTimelineAndDifferentiator() async throws {
        let repo = MockHiyaRepository()
        let p = try await repo.createPerson(name: "Alex")
        #expect(repo.people.first { $0.id == p.id }?.notes == nil)

        _ = try await repo.addPersonNote(personId: p.id, body: "climbing gym")

        #expect(repo.people.first { $0.id == p.id }?.notes == "climbing gym")
        #expect(try await repo.personNotes(personId: p.id).count == 1)
    }

    @Test func addPersonNote_secondNoteLeavesDifferentiator() async throws {
        let repo = MockHiyaRepository()
        let p = try await repo.createPerson(name: "Alex")
        let first = try await repo.addPersonNote(personId: p.id, body: "first")
        // Force `first` to be the oldest deterministically.
        backdate(repo, noteId: first.id, days: -1)

        _ = try await repo.addPersonNote(personId: p.id, body: "second")

        #expect(repo.people.first { $0.id == p.id }?.notes == "first")
    }

    @Test func updatePersonNote_onOldest_updatesDifferentiator_setsUpdatedAt_keepsCreatedAt() async throws {
        let repo = MockHiyaRepository()
        let p = try await repo.createPerson(name: "Alex")
        let first = try await repo.addPersonNote(personId: p.id, body: "first")
        let originalCreated = first.createdAt

        try await repo.updatePersonNote(id: first.id, body: "first edited")

        let updated = repo.personNoteRows.first { $0.id == first.id }!
        #expect(updated.body == "first edited")
        #expect(updated.updatedAt != nil)
        #expect(updated.createdAt == originalCreated)
        #expect(repo.people.first { $0.id == p.id }?.notes == "first edited")
    }

    @Test func updatePersonNote_onNewer_leavesDifferentiator() async throws {
        let repo = MockHiyaRepository()
        let p = try await repo.createPerson(name: "Alex")
        let first = try await repo.addPersonNote(personId: p.id, body: "first")
        backdate(repo, noteId: first.id, days: -1)
        let second = try await repo.addPersonNote(personId: p.id, body: "second")

        try await repo.updatePersonNote(id: second.id, body: "second edited")

        #expect(repo.people.first { $0.id == p.id }?.notes == "first")
    }

    @Test func deletePersonNote_oldest_promotesNext() async throws {
        let repo = MockHiyaRepository()
        let p = try await repo.createPerson(name: "Alex")
        let first = try await repo.addPersonNote(personId: p.id, body: "first")
        backdate(repo, noteId: first.id, days: -1)
        _ = try await repo.addPersonNote(personId: p.id, body: "second")

        try await repo.deletePersonNote(id: first.id)

        #expect(repo.people.first { $0.id == p.id }?.notes == "second")
    }

    @Test func deletePersonNote_last_clearsDifferentiator() async throws {
        let repo = MockHiyaRepository()
        let p = try await repo.createPerson(name: "Alex")
        let only = try await repo.addPersonNote(personId: p.id, body: "only")

        try await repo.deletePersonNote(id: only.id)

        #expect(repo.people.first { $0.id == p.id }?.notes == nil)
        #expect(try await repo.personNotes(personId: p.id).isEmpty)
    }

    @Test func createPerson_withNote_createsOneTimelineEntry() async throws {
        let repo = MockHiyaRepository()
        let p = try await repo.createPerson(name: "Alex", status: .cold, notes: "met at gym")

        let notes = try await repo.personNotes(personId: p.id)
        #expect(notes.count == 1)
        #expect(notes.first?.body == "met at gym")
        #expect(repo.people.first { $0.id == p.id }?.notes == "met at gym")
    }

    @Test func personNotes_returnsNewestFirst() async throws {
        let repo = MockHiyaRepository()
        let p = try await repo.createPerson(name: "Alex")
        let older = try await repo.addPersonNote(personId: p.id, body: "older")
        backdate(repo, noteId: older.id, days: -1)
        _ = try await repo.addPersonNote(personId: p.id, body: "newer")

        let notes = try await repo.personNotes(personId: p.id)
        #expect(notes.map(\.body) == ["newer", "older"])
    }

    @Test func personConversations_returnsOnlyThatPersonsLogsNewestFirst() async throws {
        let repo = MockHiyaRepository()
        let alex = try await repo.createPerson(name: "Alex")
        let bea = try await repo.createPerson(name: "Bea")
        let older = Calendar.current.date(byAdding: .day, value: -2, to: .now)!
        try await repo.logConversation(personId: alex.id, occurredAt: older, valence: nil, note: "first", improvementNote: nil)
        try await repo.logConversation(personId: alex.id, valence: nil, note: "second", improvementNote: nil)
        try await repo.logConversation(personId: bea.id, valence: nil, note: "bea's", improvementNote: nil)

        let convs = try await repo.personConversations(personId: alex.id)

        #expect(convs.count == 2, "only Alex's conversations")
        #expect(convs.map(\.note) == ["second", "first"], "newest first")
        #expect(convs.allSatisfy { $0.personName == "Alex" })
    }

    @Test func updateGoals_setsBothGoals() async throws {
        let repo = MockHiyaRepository()
        let updated = try await repo.updateGoals(coldDailyGoal: 3, warmDailyGoal: 8)

        #expect(updated.coldDailyGoal == 3)
        #expect(updated.warmDailyGoal == 8)
        #expect(repo.profile.coldDailyGoal == 3)
        #expect(repo.profile.warmDailyGoal == 8)
    }

    @Test func deletePerson_cascadesNotes() async throws {
        let repo = MockHiyaRepository()
        let p = try await repo.createPerson(name: "Alex", notes: "seed")
        #expect(repo.personNoteRows.contains { $0.personId == p.id })

        try await repo.deletePerson(id: p.id)

        #expect(!repo.personNoteRows.contains { $0.personId == p.id })
    }

    // MARK: - Chronological cold-flag classification (met_cold)

    @Test func metCold_earliestMeetingIsColdRestWarm() async throws {
        let repo = MockHiyaRepository()
        let p = try await repo.createPerson(name: "Angie", status: .cold, notes: nil, metCold: true)
        let cal = Calendar.current
        func day(_ ago: Int) -> Date { cal.date(byAdding: .day, value: -ago, to: .now)! }
        // Insert out of chronological order.
        try await repo.logConversation(personId: p.id, occurredAt: day(2), valence: nil, note: "gym tue", improvementNote: nil)
        try await repo.logConversation(personId: p.id, occurredAt: day(7), valence: nil, note: "met sunday", improvementNote: nil)
        try await repo.logConversation(personId: p.id, occurredAt: day(0), valence: nil, note: "gym today", improvementNote: nil)

        let sorted = repo.conversations.filter { $0.personId == p.id }.sorted { $0.occurredAt < $1.occurredAt }
        #expect(sorted.first?.note == "met sunday")
        #expect(sorted.first?.wasColdAtTime == true)
        #expect(sorted.dropFirst().allSatisfy { $0.wasColdAtTime == false })
    }

    @Test func notMetCold_allMeetingsWarm() async throws {
        let repo = MockHiyaRepository()
        let p = try await repo.createPerson(name: "Old Friend", status: .warm, notes: nil, metCold: false)
        try await repo.logConversation(personId: p.id, valence: nil, note: nil, improvementNote: nil)
        try await repo.logConversation(personId: p.id, valence: nil, note: nil, improvementNote: nil)
        #expect(repo.conversations.allSatisfy { $0.wasColdAtTime == false })
    }

    @Test func updatePersonMetCold_flipsClassification() async throws {
        let repo = MockHiyaRepository()
        let cal = Calendar.current
        let p = try await repo.createPerson(name: "Sam", status: .warm, notes: nil, metCold: false)
        try await repo.logConversation(personId: p.id, occurredAt: cal.date(byAdding: .day, value: -3, to: .now)!, valence: nil, note: "first", improvementNote: nil)
        try await repo.logConversation(personId: p.id, occurredAt: .now, valence: nil, note: "second", improvementNote: nil)
        #expect(repo.conversations.allSatisfy { $0.wasColdAtTime == false })

        try await repo.updatePersonMetCold(id: p.id, metCold: true)
        let sorted = repo.conversations.sorted { $0.occurredAt < $1.occurredAt }
        #expect(sorted.first?.wasColdAtTime == true)
        #expect(sorted.last?.wasColdAtTime == false)

        try await repo.updatePersonMetCold(id: p.id, metCold: false)
        #expect(repo.conversations.allSatisfy { $0.wasColdAtTime == false })
    }

    @Test func deletingEarliest_promotesNextEarliestToCold() async throws {
        let repo = MockHiyaRepository()
        let cal = Calendar.current
        let p = try await repo.createPerson(name: "Angie", status: .cold, notes: nil, metCold: true)
        try await repo.logConversation(personId: p.id, occurredAt: cal.date(byAdding: .day, value: -5, to: .now)!, valence: nil, note: "earliest", improvementNote: nil)
        try await repo.logConversation(personId: p.id, occurredAt: .now, valence: nil, note: "later", improvementNote: nil)
        let earliestId = repo.conversations.min { $0.occurredAt < $1.occurredAt }!.id

        try await repo.deleteConversation(id: earliestId)

        #expect(repo.conversations.count == 1)
        #expect(repo.conversations.first?.note == "later")
        #expect(repo.conversations.first?.wasColdAtTime == true)
    }

    @Test func createPerson_metCold_persists() async throws {
        let repo = MockHiyaRepository()
        let p = try await repo.createPerson(name: "X", status: .cold, notes: nil, metCold: true)
        #expect(repo.people.first(where: { $0.id == p.id })?.metCold == true)
    }

    @Test func logConversation_storesAndReturnsLocation() async throws {
        let repo = MockHiyaRepository()
        let p = try await repo.createPerson(name: "Angie", status: .warm, notes: nil, metCold: false)
        try await repo.logConversation(personId: p.id, valence: nil, note: nil, improvementNote: nil, location: "The Gym")
        let history = try await repo.personConversations(personId: p.id)
        #expect(history.first?.location == "The Gym")
    }

    @Test func logQuickApproach_logsCountedNamelessColdApproaches() async throws {
        let repo = MockHiyaRepository()
        try await repo.logQuickApproach(count: 2, occurredAt: .now, valence: .negative, note: nil, location: "e7")

        #expect(repo.conversations.count == 2)
        #expect(repo.conversations.allSatisfy { $0.wasColdAtTime }, "quick approaches are cold")
        #expect(repo.conversations.allSatisfy { $0.location == "e7" })
        #expect(repo.people.count == 2)
        #expect(repo.people.allSatisfy { $0.anonymous })
        let listed = try await repo.listPeople()
        #expect(listed.isEmpty, "anonymous people never show in the People list")
    }

    // MARK: - Accounts

    @Test func defaultAccount_isAnonymous() async {
        let repo = MockHiyaRepository()
        let acct = await repo.currentAccount()
        #expect(acct?.isAnonymous == true)
        #expect(acct?.email == nil)
    }

    @Test func claimAccount_keepsIdMakesPermanent_setsName() async throws {
        let repo = MockHiyaRepository()
        let before = await repo.currentAccount()
        let profile = try await repo.claimAccount(email: "w@x.com", password: "secret1", displayName: "William Jin")
        let after = await repo.currentAccount()
        #expect(after?.isAnonymous == false)
        #expect(after?.email == "w@x.com")
        #expect(after?.id == before?.id, "claim must preserve the user id so data stays owned")
        #expect(profile.displayName == "William Jin")
    }

    @Test func signOut_thenCurrentAccountIsNil() async throws {
        let repo = MockHiyaRepository()
        try await repo.signOut()
        let acct = await repo.currentAccount()
        #expect(acct == nil)
    }

    @Test func signIn_restoresPermanentAccount() async throws {
        let repo = MockHiyaRepository()
        try await repo.signOut()
        _ = try await repo.signIn(email: "w@x.com", password: "secret1")
        let acct = await repo.currentAccount()
        #expect(acct?.isAnonymous == false)
        #expect(acct?.email == "w@x.com")
    }

    @Test func updateDisplayName_persists() async throws {
        let repo = MockHiyaRepository()
        let p = try await repo.updateDisplayName("Will")
        #expect(p.displayName == "Will")
        #expect(repo.profile.displayName == "Will")
    }
}
