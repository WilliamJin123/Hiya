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
