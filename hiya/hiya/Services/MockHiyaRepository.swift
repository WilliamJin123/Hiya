import Foundation

@MainActor
final class MockHiyaRepository: HiyaRepository {
    var profile: Profile
    var people: [Person]
    var conversations: [Conversation]
    var challengeRows: [Challenge] = []
    var personNoteRows: [PersonNote] = []
    var authAccount: AuthAccount?

    var errorToThrow: Error?

    init(
        profile: Profile = .preview,
        people: [Person] = [],
        conversations: [Conversation] = []
    ) {
        self.profile = profile
        self.people = people
        self.conversations = conversations
        self.authAccount = AuthAccount(id: profile.id, email: nil, isAnonymous: true)
    }

    func ensureSignedIn() async throws -> Profile {
        if let err = errorToThrow { errorToThrow = nil; throw err }
        if authAccount == nil {
            authAccount = AuthAccount(id: profile.id, email: nil, isAnonymous: true)
        }
        return profile
    }

    func currentAccount() async -> AuthAccount? { authAccount }

    func claimAccount(email: String, password: String, displayName: String) async throws -> Profile {
        if let err = errorToThrow { errorToThrow = nil; throw err }
        authAccount = AuthAccount(id: profile.id, email: email, isAnonymous: false)
        profile.displayName = displayName
        return profile
    }

    func signUp(email: String, password: String, displayName: String) async throws -> Profile {
        if let err = errorToThrow { errorToThrow = nil; throw err }
        authAccount = AuthAccount(id: profile.id, email: email, isAnonymous: false)
        profile.displayName = displayName
        return profile
    }

    func signIn(email: String, password: String) async throws -> Profile {
        if let err = errorToThrow { errorToThrow = nil; throw err }
        authAccount = AuthAccount(id: profile.id, email: email, isAnonymous: false)
        return profile
    }

    func signOut() async throws {
        if let err = errorToThrow { errorToThrow = nil; throw err }
        authAccount = nil
    }

    func updateDisplayName(_ name: String) async throws -> Profile {
        if let err = errorToThrow { errorToThrow = nil; throw err }
        profile.displayName = name
        return profile
    }

    func updateGoals(coldDailyGoal: Int, warmDailyGoal: Int) async throws -> Profile {
        if let err = errorToThrow { errorToThrow = nil; throw err }
        profile.coldDailyGoal = coldDailyGoal
        profile.warmDailyGoal = warmDailyGoal
        return profile
    }

    func listPeople() async throws -> [Person] {
        if let err = errorToThrow { errorToThrow = nil; throw err }
        return people.filter { !$0.anonymous }.sorted { $0.lastLoggedAt > $1.lastLoggedAt }
    }

    func createPerson(name: String, status: PersonStatus = .cold, notes: String? = nil, metCold: Bool? = nil, anonymous: Bool = false) async throws -> Person {
        if let err = errorToThrow { errorToThrow = nil; throw err }
        let trimmedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        let seed = (trimmedNotes?.isEmpty == false) ? trimmedNotes : nil
        // A cold-status creation is a cold approach unless told otherwise.
        let resolvedMetCold = metCold ?? (status == .cold)
        let person = Person(
            id: UUID(),
            ownerId: profile.id,
            name: name,
            status: status,
            statusChangedAt: status == .warm ? .now : nil,
            notes: seed,
            metCold: resolvedMetCold,
            anonymous: anonymous,
            createdAt: .now,
            lastLoggedAt: .now
        )
        people.append(person)
        if let seed {
            personNoteRows.append(PersonNote(
                id: UUID(),
                ownerId: profile.id,
                personId: person.id,
                body: seed,
                createdAt: person.createdAt,
                updatedAt: nil
            ))
        }
        return person
    }

    func conversations(start: Date, end: Date) async throws -> [LoggedConversation] {
        if let err = errorToThrow { errorToThrow = nil; throw err }
        return conversations
            .filter { $0.occurredAt >= start && $0.occurredAt < end }
            .sorted { $0.occurredAt > $1.occurredAt }
            .map { conv in
                let name = people.first(where: { $0.id == conv.personId })?.name ?? "Unknown"
                return LoggedConversation(
                    id: conv.id,
                    personId: conv.personId,
                    personName: name,
                    occurredAt: conv.occurredAt,
                    valence: conv.valence,
                    note: conv.note,
                    improvementNote: conv.improvementNote,
                    location: conv.location,
                    wasColdAtTime: conv.wasColdAtTime
                )
            }
    }

    func personConversations(personId: UUID) async throws -> [LoggedConversation] {
        if let err = errorToThrow { errorToThrow = nil; throw err }
        return conversations
            .filter { $0.personId == personId }
            .sorted { $0.occurredAt > $1.occurredAt }
            .map { conv in
                let name = people.first(where: { $0.id == conv.personId })?.name ?? "Unknown"
                return LoggedConversation(
                    id: conv.id,
                    personId: conv.personId,
                    personName: name,
                    occurredAt: conv.occurredAt,
                    valence: conv.valence,
                    note: conv.note,
                    improvementNote: conv.improvementNote,
                    location: conv.location,
                    wasColdAtTime: conv.wasColdAtTime
                )
            }
    }

    func logConversation(
        personId: UUID,
        occurredAt: Date = .now,
        valence: Conversation.Valence?,
        note: String?,
        improvementNote: String?,
        location: String? = nil
    ) async throws {
        if let err = errorToThrow { errorToThrow = nil; throw err }
        let conv = Conversation(
            id: UUID(),
            ownerId: profile.id,
            personId: personId,
            occurredAt: occurredAt,
            valence: valence,
            note: note,
            improvementNote: improvementNote,
            location: location,
            wasColdAtTime: false,
            createdAt: .now
        )
        conversations.append(conv)
        // Mirror the DB trigger: last_logged_at only ever moves forward.
        if let idx = people.firstIndex(where: { $0.id == personId }), people[idx].lastLoggedAt < occurredAt {
            people[idx].lastLoggedAt = occurredAt
        }
        recomputeColdFlags(personId: personId)
    }

    func updatePersonStatus(id: UUID, status: PersonStatus) async throws {
        if let err = errorToThrow { errorToThrow = nil; throw err }
        if let i = people.firstIndex(where: { $0.id == id }) {
            people[i].status = status
            people[i].statusChangedAt = .now
        }
    }

    func updatePersonMetCold(id: UUID, metCold: Bool) async throws {
        if let err = errorToThrow { errorToThrow = nil; throw err }
        guard let i = people.firstIndex(where: { $0.id == id }) else { return }
        people[i].metCold = metCold
        recomputeColdFlags(personId: id)
    }

    /// Mirror the DB recompute: a met_cold person's chronologically earliest
    /// meeting is cold and the rest warm; a non-met_cold person's are all warm.
    private func recomputeColdFlags(personId: UUID) {
        guard let person = people.first(where: { $0.id == personId }) else { return }
        let mine = conversations.indices.filter { conversations[$0].personId == personId }
        for i in mine { conversations[i].wasColdAtTime = false }
        guard person.metCold else { return }
        let earliest = mine.min { a, b in
            if conversations[a].occurredAt != conversations[b].occurredAt {
                return conversations[a].occurredAt < conversations[b].occurredAt
            }
            return conversations[a].id.uuidString < conversations[b].id.uuidString
        }
        if let earliest { conversations[earliest].wasColdAtTime = true }
    }

    func reclassifyConversations(personId: UUID, wasCold: Bool) async throws {
        if let err = errorToThrow { errorToThrow = nil; throw err }
        for i in conversations.indices where conversations[i].personId == personId {
            conversations[i].wasColdAtTime = wasCold
        }
    }

    func graduatePastDuePeople(beforeLog: Date) async throws {
        if let err = errorToThrow { errorToThrow = nil; throw err }
        for idx in people.indices {
            if people[idx].status == .cold && people[idx].lastLoggedAt < beforeLog {
                people[idx].status = .warm
                people[idx].statusChangedAt = .now
            }
        }
    }

    func updateConversation(
        id: UUID,
        occurredAt: Date = .now,
        valence: Conversation.Valence?,
        note: String?,
        improvementNote: String?,
        location: String? = nil
    ) async throws {
        if let err = errorToThrow { errorToThrow = nil; throw err }
        guard let idx = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[idx].occurredAt = occurredAt
        conversations[idx].valence = valence
        conversations[idx].note = note
        conversations[idx].improvementNote = improvementNote
        conversations[idx].location = location
        recomputeColdFlags(personId: conversations[idx].personId)
    }

    func deleteConversation(id: UUID) async throws {
        if let err = errorToThrow { errorToThrow = nil; throw err }
        let personId = conversations.first(where: { $0.id == id })?.personId
        conversations.removeAll { $0.id == id }
        if let personId { recomputeColdFlags(personId: personId) }
    }

    func updatePersonNotes(id: UUID, notes: String?) async throws {
        if let err = errorToThrow { errorToThrow = nil; throw err }
        guard let idx = people.firstIndex(where: { $0.id == id }) else { return }
        people[idx].notes = notes
    }

    func personNotes(personId: UUID) async throws -> [PersonNote] {
        if let err = errorToThrow { errorToThrow = nil; throw err }
        return personNoteRows
            .filter { $0.personId == personId }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func addPersonNote(personId: UUID, body: String) async throws -> PersonNote {
        if let err = errorToThrow { errorToThrow = nil; throw err }
        let note = PersonNote(
            id: UUID(),
            ownerId: profile.id,
            personId: personId,
            body: body,
            createdAt: .now,
            updatedAt: nil
        )
        personNoteRows.append(note)
        recomputeDifferentiator(personId: personId)
        return note
    }

    func updatePersonNote(id: UUID, body: String) async throws {
        if let err = errorToThrow { errorToThrow = nil; throw err }
        guard let idx = personNoteRows.firstIndex(where: { $0.id == id }) else { return }
        personNoteRows[idx].body = body
        personNoteRows[idx].updatedAt = .now
        recomputeDifferentiator(personId: personNoteRows[idx].personId)
    }

    func deletePersonNote(id: UUID) async throws {
        if let err = errorToThrow { errorToThrow = nil; throw err }
        guard let note = personNoteRows.first(where: { $0.id == id }) else { return }
        let personId = note.personId
        personNoteRows.removeAll { $0.id == id }
        recomputeDifferentiator(personId: personId)
    }

    /// Keep `Person.notes` equal to the oldest remaining note's body (the
    /// duplicate-name differentiator), or nil when the person has no notes.
    private func recomputeDifferentiator(personId: UUID) {
        guard let pIdx = people.firstIndex(where: { $0.id == personId }) else { return }
        let oldest = personNoteRows
            .filter { $0.personId == personId }
            .min(by: { $0.createdAt < $1.createdAt })
        people[pIdx].notes = oldest?.body
    }

    func deletePerson(id: UUID) async throws {
        if let err = errorToThrow { errorToThrow = nil; throw err }
        // Mirror the DB cascade — removing a person also removes their logs and notes.
        people.removeAll { $0.id == id }
        conversations.removeAll { $0.personId == id }
        personNoteRows.removeAll { $0.personId == id }
    }

    func recentConversationActivity(since: Date) async throws -> [ConversationActivity] {
        if let err = errorToThrow { errorToThrow = nil; throw err }
        return conversations
            .filter { $0.occurredAt >= since }
            .map { ConversationActivity(occurredAt: $0.occurredAt, wasColdAtTime: $0.wasColdAtTime) }
    }

    func followUpSuggestions(thresholdDays: Int, limit: Int) async throws -> [Person] {
        if let err = errorToThrow { errorToThrow = nil; throw err }
        let threshold = Calendar.current.date(byAdding: .day, value: -thresholdDays, to: .now) ?? .now
        return Array(
            people
                .filter { $0.status == .warm && !$0.anonymous && $0.lastLoggedAt < threshold }
                .sorted { $0.lastLoggedAt < $1.lastLoggedAt }
                .prefix(limit)
        )
    }

    func challenges() async throws -> [Challenge] {
        if let err = errorToThrow { errorToThrow = nil; throw err }
        return challengeRows.sorted { $0.startedAt > $1.startedAt }
    }

    func startChallenge(_ draft: ChallengeDraft) async throws -> Challenge {
        if let err = errorToThrow { errorToThrow = nil; throw err }
        let c = Challenge(
            id: UUID(),
            ownerId: profile.id,
            title: draft.title,
            prompt: draft.prompt,
            track: draft.track,
            targetCount: draft.targetCount,
            durationDays: draft.durationDays,
            source: draft.source,
            templateSlug: draft.templateSlug,
            startedAt: .now,
            completedAt: nil
        )
        challengeRows.append(c)
        return c
    }

    func completeChallenge(id: UUID) async throws {
        if let err = errorToThrow { errorToThrow = nil; throw err }
        if let i = challengeRows.firstIndex(where: { $0.id == id }) {
            challengeRows[i].completedAt = .now
        }
    }

    func abandonChallenge(id: UUID) async throws {
        if let err = errorToThrow { errorToThrow = nil; throw err }
        challengeRows.removeAll { $0.id == id }
    }
}

extension Profile {
    nonisolated static let preview = Profile(
        id: UUID(),
        displayName: nil,
        dailyGoal: 10,
        streakMode: .hard,
        timezone: TimeZone.current.identifier,
        createdAt: .now
    )
}
