import Foundation

enum ChallengeTrack: String, Codable, Sendable, Equatable, CaseIterable {
    case cold, warm, any
}

/// A built-in challenge definition. Templates live in-app as constants; a row
/// in the `challenges` table is only created once a template is *started*.
struct ChallengeTemplate: Identifiable, Sendable, Equatable {
    let slug: String
    let title: String
    let prompt: String
    let track: ChallengeTrack
    let targetCount: Int?
    let durationDays: Int?

    var id: String { slug }

    static let catalog: [ChallengeTemplate] = [
        .init(slug: "open-question", title: "Open with a question",
              prompt: "Start a conversation with an open-ended question.",
              track: .cold, targetCount: nil, durationDays: nil),
        .init(slug: "genuine-compliment", title: "Genuine compliment",
              prompt: "Give someone you don't know a sincere compliment.",
              track: .cold, targetCount: nil, durationDays: nil),
        .init(slug: "three-new-faces", title: "Three new faces",
              prompt: "Approach three new people this week.",
              track: .cold, targetCount: 3, durationDays: 7),
        .init(slug: "one-today", title: "One today",
              prompt: "Approach one new person today.",
              track: .cold, targetCount: 1, durationDays: 1),
        .init(slug: "go-deeper", title: "Go deeper",
              prompt: "Ask a catch-up about something beyond small talk.",
              track: .warm, targetCount: nil, durationDays: nil),
        .init(slug: "reconnect-x2", title: "Reconnect ×2",
              prompt: "Catch up with two people you've lost touch with this week.",
              track: .warm, targetCount: 2, durationDays: 7),
        .init(slug: "phone-away", title: "Phone away",
              prompt: "Have a full conversation without checking your phone.",
              track: .any, targetCount: nil, durationDays: nil),
        .init(slug: "listen-more", title: "Listen more",
              prompt: "Spend a conversation mostly listening.",
              track: .any, targetCount: nil, durationDays: nil),
    ]
}
