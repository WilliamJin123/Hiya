import SwiftUI

/// Centralized design tokens. Every color, font, radius, and spacing value in the
/// app should come from here. If you find yourself reaching for a literal
/// (e.g. `Color.blue`, `radius: 12`), add a token here instead.
enum Theme {

    // MARK: - Colors

    static let bgGradientTop      = Color(red: 14/255,  green: 11/255,  blue: 20/255)
    static let bgGradientBottom   = Color(red: 27/255,  green: 23/255,  blue: 38/255)
    static let surface            = Color(red: 31/255,  green: 26/255,  blue: 42/255)

    static let textPrimary        = Color(red: 233/255, green: 228/255, blue: 240/255)
    static let textSecondary      = Color(red: 141/255, green: 133/255, blue: 163/255)
    static let textOnAccent       = Color(red: 20/255,  green: 17/255,  blue: 27/255)

    static let accentLavender     = Color(red: 184/255, green: 167/255, blue: 232/255)
    static let accentAmber        = Color(red: 246/255, green: 193/255, blue: 119/255)

    static let valencePositive    = Color(red: 167/255, green: 217/255, blue: 181/255)
    static let valenceNeutral     = Color(red: 246/255, green: 193/255, blue: 119/255)
    static let valenceNegative    = Color(red: 224/255, green: 145/255, blue: 139/255)
    static let valenceNone        = Color(red: 74/255,  green: 67/255,  blue: 88/255)

    static let divider            = Color.white.opacity(0.08)
    static let ringTrack          = Color.white.opacity(0.07)

    static let bgGradient = LinearGradient(
        colors: [bgGradientTop, bgGradientBottom],
        startPoint: .top, endPoint: .bottom
    )

    static let accentGradient = LinearGradient(
        colors: [accentLavender, accentAmber],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// Amber→lavender (warm-leading). Used for the Approaches ring: cold
    /// approaches get the warmer-feeling sweep to make the hard thing inviting,
    /// while Catch-ups get the cooler `accentGradient` — a deliberate oxymoron.
    static let accentGradientReversed = LinearGradient(
        colors: [accentAmber, accentLavender],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    // MARK: - Semantic mode accents
    //
    // Approaches (cold) read cool; Catch-ups (warm) read warm. Neutral chrome
    // (tab tint, buttons, gear) keeps using `accentLavender` directly — it is
    // not a cold/warm signal. Flip both lines below to re-theme the modes.
    static let coldAccent = accentLavender
    static let warmAccent = accentAmber

    /// Deeper, more saturated lavender for the "pure cold" sub-goal (hard mode).
    /// Reads as cold *intensified* — same family as `coldAccent`, pushed harder —
    /// so the inner Approaches ring looks like a tougher tier, not a new mode.
    static let pureColdAccent = Color(red: 149/255, green: 122/255, blue: 224/255)

    static func accent(for status: PersonStatus) -> Color {
        status == .cold ? coldAccent : warmAccent
    }

    /// Ring gradient per mode: each leads with its own mode's color. (Cold leads
    /// lavender via `accentGradient`; warm leads amber via `accentGradientReversed`.)
    static func gradient(for status: PersonStatus) -> LinearGradient {
        status == .cold ? accentGradient : accentGradientReversed
    }

    // MARK: - Font PostScript names
    //
    // Verify in Font Book (open the TTF, ⌘I on the selected face). If a name
    // differs at runtime — e.g. SwiftUI logs "CTFontCreateForCSS could not find
    // family DMSans-Regular" — change the constant here and rebuild.

    enum FontName {
        static let titleSerif   = "InstrumentSerif-Regular"
        /// Vercel's Geist — picked to match the existing `GeistMono` counters,
        /// so numbers and text now belong to the same family. Modern with a
        /// little character (cut counters on `a`, distinctive `g` descender)
        /// while staying very legible. Replaces DM Sans.
        static let bodySans     = "Geist-Regular"
        static let counterMono  = "GeistMono-Regular"
    }

    // MARK: - Type scale

    enum FontScale {
        static func title() -> Font {
            .custom(FontName.titleSerif, size: 32)
        }
        /// The "Hiya" wordmark — soft rounded letterforms for a friendly,
        /// playful greeting. Pair with `Theme.accentGradient` as the fill.
        static func wordmark() -> Font {
            .system(size: 30, weight: .bold, design: .rounded)
        }
        static func counter() -> Font {
            .custom(FontName.counterMono, size: 72).weight(.semibold)
        }
        static func counterOverload() -> Font {
            .custom(FontName.counterMono, size: 60).weight(.semibold)
        }
        static func goalStar() -> Font {
            .custom(FontName.titleSerif, size: 84)
        }
        static func bodyHeading() -> Font {
            .custom(FontName.bodySans, size: 14).weight(.semibold)
        }
        static func body() -> Font {
            .custom(FontName.bodySans, size: 16).weight(.medium)
        }
        static func secondary() -> Font {
            .custom(FontName.bodySans, size: 13).weight(.medium)
        }
        static func micro() -> Font {
            .custom(FontName.bodySans, size: 11).weight(.semibold)
        }
    }

    // MARK: - Radii

    enum Radius {
        static let sm: CGFloat = 10
        static let md: CGFloat = 14
        static let lg: CGFloat = 20
    }

    // MARK: - Spacing

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }

    // MARK: - Glow / shadow

    enum Glow {
        static let inProgressColor = Theme.accentLavender.opacity(0.4)
        static let atGoalColor     = Theme.accentAmber.opacity(0.45)
        static let overloadColor   = Theme.accentAmber.opacity(0.55)
        static let blur: CGFloat   = 22
    }
}
