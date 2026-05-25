import Foundation

protocol HiyaRepository: Sendable {
    func ensureSignedIn() async throws -> Profile
    func updateGoals(coldDailyGoal: Int, warmDailyGoal: Int) async throws -> Profile
    func listPeople() async throws -> [Person]
    func createPerson(name: String, status: PersonStatus, notes: String?) async throws -> Person
    func conversations(start: Date, end: Date) async throws -> [LoggedConversation]
    func personConversations(personId: UUID) async throws -> [LoggedConversation]
    func logConversation(
        personId: UUID,
        occurredAt: Date,
        valence: Conversation.Valence?,
        note: String?,
        improvementNote: String?
    ) async throws
    func updateConversation(
        id: UUID,
        occurredAt: Date,
        valence: Conversation.Valence?,
        note: String?,
        improvementNote: String?
    ) async throws
    func deleteConversation(id: UUID) async throws
    func deletePerson(id: UUID) async throws
    func updatePersonNotes(id: UUID, notes: String?) async throws
    func personNotes(personId: UUID) async throws -> [PersonNote]
    func addPersonNote(personId: UUID, body: String) async throws -> PersonNote
    func updatePersonNote(id: UUID, body: String) async throws
    func deletePersonNote(id: UUID) async throws
    func updatePersonStatus(id: UUID, status: PersonStatus) async throws
    func reclassifyConversations(personId: UUID, wasCold: Bool) async throws
    func graduatePastDuePeople(beforeLog: Date) async throws
    func recentConversationActivity(since: Date) async throws -> [ConversationActivity]
    func followUpSuggestions(thresholdDays: Int, limit: Int) async throws -> [Person]
    func challenges() async throws -> [Challenge]
    func startChallenge(_ draft: ChallengeDraft) async throws -> Challenge
    func completeChallenge(id: UUID) async throws
    func abandonChallenge(id: UUID) async throws
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

    func updateGoals(coldDailyGoal: Int, warmDailyGoal: Int) async throws -> Profile {
        let userId = try await client.auth.user().id
        struct Update: Encodable {
            let cold_daily_goal: Int
            let warm_daily_goal: Int
        }
        return try await client
            .from("profiles")
            .update(Update(cold_daily_goal: coldDailyGoal, warm_daily_goal: warmDailyGoal))
            .eq("id", value: userId)
            .select()
            .single()
            .execute()
            .value
    }

    func listPeople() async throws -> [Person] {
        try await client
            .from("people")
            .select()
            .order("last_logged_at", ascending: false)
            .execute()
            .value
    }

    func createPerson(name: String, status: PersonStatus = .cold, notes: String? = nil) async throws -> Person {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        let seed = (trimmedNotes?.isEmpty == false) ? trimmedNotes : nil
        let userId = try await client.auth.user().id
        struct Insert: Encodable {
            let owner_id: UUID
            let name: String
            let status: String
            let status_changed_at: String?
            let notes: String?
        }
        let inserted: Person = try await client
            .from("people")
            .insert(Insert(
                owner_id: userId,
                name: trimmed,
                status: status.rawValue,
                status_changed_at: status == .warm ? Date.now.iso8601String : nil,
                notes: seed
            ))
            .select()
            .single()
            .execute()
            .value
        if let seed {
            struct NoteInsert: Encodable {
                let owner_id: UUID
                let person_id: UUID
                let body: String
                let created_at: String
            }
            try await client
                .from("person_notes")
                .insert(NoteInsert(
                    owner_id: userId,
                    person_id: inserted.id,
                    body: seed,
                    created_at: inserted.createdAt.iso8601String
                ))
                .execute()
        }
        return inserted
    }

    func conversations(start: Date, end: Date) async throws -> [LoggedConversation] {
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

    func personConversations(personId: UUID) async throws -> [LoggedConversation] {
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
            .eq("person_id", value: personId)
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
        occurredAt: Date = .now,
        valence: Conversation.Valence?,
        note: String?,
        improvementNote: String?
    ) async throws {
        let userId = try await client.auth.user().id
        struct Insert: Encodable {
            let owner_id: UUID
            let person_id: UUID
            let occurred_at: String
            let valence: Conversation.Valence?
            let note: String?
            let improvement_note: String?
        }
        try await client
            .from("conversations")
            .insert(Insert(
                owner_id: userId,
                person_id: personId,
                occurred_at: occurredAt.iso8601String,
                valence: valence,
                note: note,
                improvement_note: improvementNote
            ))
            .execute()
    }

    func updateConversation(
        id: UUID,
        occurredAt: Date = .now,
        valence: Conversation.Valence?,
        note: String?,
        improvementNote: String?
    ) async throws {
        struct Update: Encodable {
            let occurred_at: String
            let valence: Conversation.Valence?
            let note: String?
            let improvement_note: String?
        }
        try await client
            .from("conversations")
            .update(Update(
                occurred_at: occurredAt.iso8601String,
                valence: valence,
                note: note,
                improvement_note: improvementNote
            ))
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

    func updatePersonNotes(id: UUID, notes: String?) async throws {
        struct Update: Encodable { let notes: String? }
        try await client
            .from("people")
            .update(Update(notes: notes))
            .eq("id", value: id)
            .execute()
    }

    func personNotes(personId: UUID) async throws -> [PersonNote] {
        try await client
            .from("person_notes")
            .select()
            .eq("person_id", value: personId)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func addPersonNote(personId: UUID, body: String) async throws -> PersonNote {
        let userId = try await client.auth.user().id
        struct Insert: Encodable {
            let owner_id: UUID
            let person_id: UUID
            let body: String
        }
        let inserted: PersonNote = try await client
            .from("person_notes")
            .insert(Insert(owner_id: userId, person_id: personId, body: body))
            .select()
            .single()
            .execute()
            .value
        try await recomputeDifferentiator(personId: personId)
        return inserted
    }

    func updatePersonNote(id: UUID, body: String) async throws {
        struct Update: Encodable {
            let body: String
            let updated_at: String
        }
        struct Row: Decodable { let person_id: UUID }
        let row: Row = try await client
            .from("person_notes")
            .update(Update(body: body, updated_at: Date.now.iso8601String))
            .eq("id", value: id)
            .select("person_id")
            .single()
            .execute()
            .value
        try await recomputeDifferentiator(personId: row.person_id)
    }

    func deletePersonNote(id: UUID) async throws {
        struct Row: Decodable { let person_id: UUID }
        let row: Row = try await client
            .from("person_notes")
            .delete()
            .eq("id", value: id)
            .select("person_id")
            .single()
            .execute()
            .value
        try await recomputeDifferentiator(personId: row.person_id)
    }

    /// Keep `people.notes` equal to the oldest note's body (the duplicate-name
    /// differentiator), or null when the person has no notes.
    private func recomputeDifferentiator(personId: UUID) async throws {
        struct Row: Decodable { let body: String }
        let rows: [Row] = try await client
            .from("person_notes")
            .select("body")
            .eq("person_id", value: personId)
            .order("created_at", ascending: true)
            .limit(1)
            .execute()
            .value
        try await updatePersonNotes(id: personId, notes: rows.first?.body)
    }

    func updatePersonStatus(id: UUID, status: PersonStatus) async throws {
        struct Update: Encodable {
            let status: String
            let status_changed_at: String
        }
        try await client
            .from("people")
            .update(Update(status: status.rawValue, status_changed_at: Date.now.iso8601String))
            .eq("id", value: id)
            .execute()
    }

    func reclassifyConversations(personId: UUID, wasCold: Bool) async throws {
        struct Update: Encodable { let was_cold_at_time: Bool }
        try await client
            .from("conversations")
            .update(Update(was_cold_at_time: wasCold))
            .eq("person_id", value: personId)
            .execute()
    }

    func graduatePastDuePeople(beforeLog: Date) async throws {
        struct Update: Encodable {
            let status: String
            let status_changed_at: String
        }
        try await client
            .from("people")
            .update(Update(status: "warm", status_changed_at: Date.now.iso8601String))
            .eq("status", value: "cold")
            .lt("last_logged_at", value: beforeLog.iso8601String)
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

    func followUpSuggestions(thresholdDays: Int, limit: Int) async throws -> [Person] {
        let threshold = Calendar.current.date(byAdding: .day, value: -thresholdDays, to: .now) ?? .now
        return try await client
            .from("people")
            .select()
            .eq("status", value: "warm")
            .lt("last_logged_at", value: threshold.iso8601String)
            .order("last_logged_at", ascending: true)
            .limit(limit)
            .execute()
            .value
    }

    func challenges() async throws -> [Challenge] {
        try await client
            .from("challenges")
            .select()
            .order("started_at", ascending: false)
            .execute()
            .value
    }

    func startChallenge(_ draft: ChallengeDraft) async throws -> Challenge {
        let userId = try await client.auth.user().id
        struct Insert: Encodable {
            let owner_id: UUID
            let title: String
            let prompt: String
            let track: String
            let target_count: Int?
            let duration_days: Int?
            let source: String
            let template_slug: String?
        }
        return try await client
            .from("challenges")
            .insert(Insert(
                owner_id: userId,
                title: draft.title,
                prompt: draft.prompt,
                track: draft.track.rawValue,
                target_count: draft.targetCount,
                duration_days: draft.durationDays,
                source: draft.source.rawValue,
                template_slug: draft.templateSlug
            ))
            .select()
            .single()
            .execute()
            .value
    }

    func completeChallenge(id: UUID) async throws {
        struct Update: Encodable { let completed_at: String }
        try await client
            .from("challenges")
            .update(Update(completed_at: Date.now.iso8601String))
            .eq("id", value: id)
            .execute()
    }

    func abandonChallenge(id: UUID) async throws {
        try await client
            .from("challenges")
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
