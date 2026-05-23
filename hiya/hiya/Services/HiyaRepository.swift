import Foundation

protocol HiyaRepository: Sendable {
    func ensureSignedIn() async throws -> Profile
    func listPeople() async throws -> [Person]
    func createPerson(name: String) async throws -> Person
    func todaysLog(start: Date, end: Date) async throws -> [LoggedConversation]
    func logConversation(
        personId: UUID,
        valence: Conversation.Valence?,
        note: String?,
        improvementNote: String?
    ) async throws
    func updateConversation(
        id: UUID,
        valence: Conversation.Valence?,
        note: String?,
        improvementNote: String?
    ) async throws
    func deleteConversation(id: UUID) async throws
    func promotePerson(id: UUID) async throws
    func demotePerson(id: UUID) async throws
    func deletePerson(id: UUID) async throws
    func recentConversationActivity(since: Date) async throws -> [ConversationActivity]
}

struct LoggedConversation: Identifiable, Sendable, Equatable {
    let id: UUID
    let personId: UUID
    let personName: String
    let occurredAt: Date
    let valence: Conversation.Valence?
    let note: String?
    let improvementNote: String?
    let wasColdAtTime: Bool

    init(
        id: UUID,
        personId: UUID,
        personName: String,
        occurredAt: Date,
        valence: Conversation.Valence?,
        note: String?,
        improvementNote: String?,
        wasColdAtTime: Bool = false
    ) {
        self.id = id
        self.personId = personId
        self.personName = personName
        self.occurredAt = occurredAt
        self.valence = valence
        self.note = note
        self.improvementNote = improvementNote
        self.wasColdAtTime = wasColdAtTime
    }
}

import Supabase

final class LiveHiyaRepository: HiyaRepository {
    let client: SupabaseClient

    init(client: SupabaseClient = .hiya) {
        self.client = client
    }

    func ensureSignedIn() async throws -> Profile {
        if client.auth.currentSession == nil {
            try await client.auth.signInAnonymously()
        }
        let userId = try await client.auth.user().id
        let profile: Profile = try await client
            .from("profiles")
            .select()
            .eq("id", value: userId)
            .single()
            .execute()
            .value
        return profile
    }

    func listPeople() async throws -> [Person] {
        try await client
            .from("people")
            .select()
            .order("last_logged_at", ascending: false)
            .execute()
            .value
    }

    func createPerson(name: String) async throws -> Person {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let userId = try await client.auth.user().id
        struct Insert: Encodable { let owner_id: UUID; let name: String }
        let inserted: Person = try await client
            .from("people")
            .insert(Insert(owner_id: userId, name: trimmed))
            .select()
            .single()
            .execute()
            .value
        return inserted
    }

    func todaysLog(start: Date, end: Date) async throws -> [LoggedConversation] {
        struct Row: Decodable {
            let id: UUID
            let person_id: UUID
            let occurred_at: Date
            let valence: Conversation.Valence?
            let note: String?
            let improvement_note: String?
            let was_cold_at_time: Bool
            let people: PersonName
            struct PersonName: Decodable { let name: String }
        }
        let rows: [Row] = try await client
            .from("conversations")
            .select("id, person_id, occurred_at, valence, note, improvement_note, was_cold_at_time, people(name)")
            .gte("occurred_at", value: start.iso8601String)
            .lt("occurred_at", value: end.iso8601String)
            .order("occurred_at", ascending: false)
            .execute()
            .value
        return rows.map {
            LoggedConversation(
                id: $0.id,
                personId: $0.person_id,
                personName: $0.people.name,
                occurredAt: $0.occurred_at,
                valence: $0.valence,
                note: $0.note,
                improvementNote: $0.improvement_note,
                wasColdAtTime: $0.was_cold_at_time
            )
        }
    }

    func logConversation(
        personId: UUID,
        valence: Conversation.Valence?,
        note: String?,
        improvementNote: String?
    ) async throws {
        let userId = try await client.auth.user().id
        struct Insert: Encodable {
            let owner_id: UUID
            let person_id: UUID
            let valence: Conversation.Valence?
            let note: String?
            let improvement_note: String?
        }
        try await client
            .from("conversations")
            .insert(Insert(
                owner_id: userId,
                person_id: personId,
                valence: valence,
                note: note,
                improvement_note: improvementNote
            ))
            .execute()
    }

    func updateConversation(
        id: UUID,
        valence: Conversation.Valence?,
        note: String?,
        improvementNote: String?
    ) async throws {
        struct Update: Encodable {
            let valence: Conversation.Valence?
            let note: String?
            let improvement_note: String?
        }
        try await client
            .from("conversations")
            .update(Update(valence: valence, note: note, improvement_note: improvementNote))
            .eq("id", value: id)
            .execute()
    }

    func deleteConversation(id: UUID) async throws {
        try await client
            .from("conversations")
            .delete()
            .eq("id", value: id)
            .execute()
    }

    func promotePerson(id: UUID) async throws {
        try await setPersonStatus(id: id, status: "warm")
    }

    func demotePerson(id: UUID) async throws {
        try await setPersonStatus(id: id, status: "cold")
    }

    private func setPersonStatus(id: UUID, status: String) async throws {
        struct Update: Encodable { let status: String; let status_changed_at: String }
        try await client
            .from("people")
            .update(Update(status: status, status_changed_at: Date.now.iso8601String))
            .eq("id", value: id)
            .execute()
    }

    func deletePerson(id: UUID) async throws {
        try await client
            .from("people")
            .delete()
            .eq("id", value: id)
            .execute()
    }

    func recentConversationActivity(since: Date) async throws -> [ConversationActivity] {
        struct Row: Decodable {
            let occurred_at: Date
            let was_cold_at_time: Bool
        }
        let rows: [Row] = try await client
            .from("conversations")
            .select("occurred_at, was_cold_at_time")
            .gte("occurred_at", value: since.iso8601String)
            .order("occurred_at", ascending: false)
            .execute()
            .value
        return rows.map {
            ConversationActivity(occurredAt: $0.occurred_at, wasColdAtTime: $0.was_cold_at_time)
        }
    }
}

extension SupabaseClient {
    static let hiya: SupabaseClient = {
        SupabaseClient(supabaseURL: SupabaseConfig.url, supabaseKey: SupabaseConfig.anonKey)
    }()
}

extension Date {
    var iso8601String: String {
        ISO8601DateFormatter.hiya.string(from: self)
    }
}

extension ISO8601DateFormatter {
    static let hiya: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
