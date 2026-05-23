import Foundation

@MainActor
final class MockHiyaRepository: HiyaRepository {
    var profile: Profile
    var people: [Person]
    var conversations: [Conversation]

    var errorToThrow: Error?

    init(
        profile: Profile = .preview,
        people: [Person] = [],
        conversations: [Conversation] = []
    ) {
        self.profile = profile
        self.people = people
        self.conversations = conversations
    }

    func ensureSignedIn() async throws -> Profile {
        if let err = errorToThrow { errorToThrow = nil; throw err }
        return profile
    }

    func listPeople() async throws -> [Person] {
        if let err = errorToThrow { errorToThrow = nil; throw err }
        return people.sorted { $0.lastLoggedAt > $1.lastLoggedAt }
    }

    func createPerson(name: String) async throws -> Person {
        if let err = errorToThrow { errorToThrow = nil; throw err }
        let person = Person(
            id: UUID(),
            ownerId: profile.id,
            name: name,
            status: .cold,
            statusChangedAt: nil,
            createdAt: .now,
            lastLoggedAt: .now
        )
        people.append(person)
        return person
    }

    func todaysLog(start: Date, end: Date) async throws -> [LoggedConversation] {
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
                    wasColdAtTime: conv.wasColdAtTime
                )
            }
    }

    func logConversation(
        personId: UUID,
        valence: Conversation.Valence?,
        note: String?,
        improvementNote: String?
    ) async throws {
        if let err = errorToThrow { errorToThrow = nil; throw err }
        // Mirror the DB BEFORE INSERT trigger: snapshot person.status onto
        // was_cold_at_time. We no longer auto-graduate here — graduation is
        // lazy and time-based, run by graduatePastDuePeople(beforeLog:).
        let currentStatus = people.first(where: { $0.id == personId })?.status ?? .warm
        let wasCold = (currentStatus == .cold)
        let conv = Conversation(
            id: UUID(),
            ownerId: profile.id,
            personId: personId,
            occurredAt: .now,
            valence: valence,
            note: note,
            improvementNote: improvementNote,
            wasColdAtTime: wasCold,
            createdAt: .now
        )
        conversations.append(conv)
        if let idx = people.firstIndex(where: { $0.id == personId }) {
            people[idx].lastLoggedAt = conv.occurredAt
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
        valence: Conversation.Valence?,
        note: String?,
        improvementNote: String?
    ) async throws {
        if let err = errorToThrow { errorToThrow = nil; throw err }
        guard let idx = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[idx].valence = valence
        conversations[idx].note = note
        conversations[idx].improvementNote = improvementNote
    }

    func deleteConversation(id: UUID) async throws {
        if let err = errorToThrow { errorToThrow = nil; throw err }
        conversations.removeAll { $0.id == id }
    }

    func updatePersonNotes(id: UUID, notes: String?) async throws {
        if let err = errorToThrow { errorToThrow = nil; throw err }
        guard let idx = people.firstIndex(where: { $0.id == id }) else { return }
        people[idx].notes = notes
    }

    func deletePerson(id: UUID) async throws {
        if let err = errorToThrow { errorToThrow = nil; throw err }
        // Mirror the DB cascade — removing a person also removes their logs.
        people.removeAll { $0.id == id }
        conversations.removeAll { $0.personId == id }
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
                .filter { $0.status == .warm && $0.lastLoggedAt < threshold }
                .sorted { $0.lastLoggedAt < $1.lastLoggedAt }
                .prefix(limit)
        )
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
