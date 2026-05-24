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

    // MARK: - Font PostScript names
    //
    // Verify in Font Book (open the TTF, ⌘I on the selected face). If a name
    // differs at runtime — e.g. SwiftUI logs "CTFontCreateForCSS could not find
    // family DMSans-Regular" — change the constant here and rebuild.

    enum FontName {
        static let titleSerif   = "InstrumentSerif-Regular"
        static let bodySans     = "DMSans-Regular"
        static let counterMono  = "GeistMono-Regular"
    }

    // MARK: - Type scale

    enum FontScale {
        static func title() -> Font {
            .custom(FontName.titleSerif, size: 32)
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
