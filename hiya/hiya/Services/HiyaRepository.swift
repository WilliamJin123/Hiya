import Foundation

protocol HiyaRepository: Sendable {
    /// Returns the current user's profile, signing in anonymously if no session exists.
    func ensureSignedIn() async throws -> Profile

    /// All people the user has logged, sorted by `lastLoggedAt` descending.
    func listPeople() async throws -> [Person]

    /// Creates a new person and returns it.
    func createPerson(name: String) async throws -> Person

    /// Count of conversations whose `occurred_at` falls within [start, end).
    func conversationCount(start: Date, end: Date) async throws -> Int

    /// All conversations within [start, end), most recent first, joined with person name.
    func todaysLog(start: Date, end: Date) async throws -> [LoggedConversation]

    /// Inserts a conversation. `occurredAt` defaults to now.
    func logConversation(personId: UUID, valence: Conversation.Valence?, note: String?) async throws
}

/// A conversation augmented with the person's name for display.
struct LoggedConversation: Identifiable, Sendable, Equatable {
    let id: UUID
    let personName: String
    let occurredAt: Date
    let valence: Conversation.Valence?
    let note: String?
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
            let occurred_at: Date
            let valence: Conversation.Valence?
            let note: String?
            let people: PersonName
            struct PersonName: Decodable { let name: String }
        }
        let rows: [Row] = try await client
            .from("conversations")
            .select("id, occurred_at, valence, note, people(name)")
            .gte("occurred_at", value: start.iso8601String)
            .lt("occurred_at", value: end.iso8601String)
            .order("occurred_at", ascending: false)
            .execute()
            .value
        return rows.map {
            LoggedConversation(
                id: $0.id,
                personName: $0.people.name,
                occurredAt: $0.occurred_at,
                valence: $0.valence,
                note: $0.note
            )
        }
    }

    func logConversation(personId: UUID, valence: Conversation.Valence?, note: String?) async throws {
        let userId = try await client.auth.user().id
        struct Insert: Encodable {
            let owner_id: UUID
            let person_id: UUID
            let valence: Conversation.Valence?
            let note: String?
        }
        try await client
            .from("conversations")
            .insert(Insert(owner_id: userId, person_id: personId, valence: valence, note: note))
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
