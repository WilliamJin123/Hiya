import Foundation

protocol HiyaRepository: Sendable {
    func ensureSignedIn() async throws -> Profile
    func listPeople() async throws -> [Person]
    func createPerson(name: String) async throws -> Person
    func conversationCount(start: Date, end: Date) async throws -> Int
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
}

struct LoggedConversation: Identifiable, Sendable, Equatable {
    let id: UUID
    let personId: UUID
    let personName: String
    let occurredAt: Date
    let valence: Conversation.Valence?
    let note: String?
    let improvementNote: String?
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

    func conversationCount(start: Date, end: Date) async throws -> Int {
        let response = try await client
            .from("conversations")
            .select("id", head: true, count: .exact)
            .gte("occurred_at", value: start.iso8601String)
            .lt("occurred_at", value: end.iso8601String)
            .execute()
        return response.count ?? 0
    }

    func todaysLog(start: Date, end: Date) async throws -> [LoggedConversation] {
        struct Row: Decodable {
            let id: UUID
            let person_id: UUID
            let occurred_at: Date
            let valence: Conversation.Valence?
            let note: String?
            let improvement_note: String?
            let people: PersonName
            struct PersonName: Decodable { let name: String }
        }
        let rows: [Row] = try await client
            .from("conversations")
            .select("id, person_id, occurred_at, valence, note, improvement_note, people(name)")
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
                improvementNote: $0.improvement_note
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
