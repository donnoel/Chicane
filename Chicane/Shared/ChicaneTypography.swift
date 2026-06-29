import SwiftUI

enum ChicaneTypography {
    static let screenTitle = interface(.title2, weight: .bold)
    static let heroEyebrow = display(.caption, weight: .bold)
    static let heroKicker = display(.title3, weight: .bold)
    static let heroSubtitle = interface(.headline, weight: .semibold)

    static let cardTitle = interface(.headline, weight: .semibold)
    static let cardTitleStrong = interface(.title3, weight: .bold)
    static let sectionTitle = interface(.subheadline, weight: .semibold)

    static let body = interface(.body)
    static let bodyMedium = interface(.body, weight: .medium)
    static let bodySemibold = interface(.body, weight: .semibold)
    static let bodyBold = interface(.body, weight: .bold)

    static let subtitle = interface(.subheadline)
    static let subtitleMedium = interface(.subheadline, weight: .medium)
    static let subtitleSemibold = interface(.subheadline, weight: .semibold)
    static let footnote = interface(.footnote)
    static let footnoteSemibold = interface(.footnote, weight: .semibold)
    static let footnoteBold = interface(.footnote, weight: .bold)

    static let caption = interface(.caption)
    static let captionSemibold = interface(.caption, weight: .semibold)
    static let captionBold = interface(.caption, weight: .bold)
    static let captionHeavy = display(.caption, weight: .black)
    static let caption2 = interface(.caption2)
    static let caption2Semibold = interface(.caption2, weight: .semibold)
    static let caption2Bold = interface(.caption2, weight: .bold)
    static let caption2Heavy = display(.caption2, weight: .black)

    static let button = interface(.subheadline, weight: .semibold)
    static let badge = display(.caption2, weight: .semibold)
    static let badgeStrong = display(.caption2, weight: .bold)
    static let chip = display(.caption, weight: .bold)
    static let initialsSmall = display(.caption2, weight: .black)
    static let initials = display(.subheadline, weight: .bold)
    static let initialsLarge = display(.headline, weight: .black)

    static let medalNumber = display(.callout, weight: .black)
    static let score = display(.body, weight: .bold).monospacedDigit()
    static let leaderScore = display(.title2, weight: .bold).monospacedDigit()
    static let countdownNumber = display(.title, weight: .bold).monospacedDigit()
    static let countdownLabel = Font.system(size: 9, weight: .semibold, design: .rounded)
    static let leagueCode = Font.system(.body, design: .monospaced)

    static let splashStatus = display(.callout, weight: .semibold)
    static let splashEyebrow = Font.system(size: 10, weight: .heavy, design: .rounded)
    static let splashLogo = Font.system(size: 44, weight: .black, design: .rounded)

    static func heroTitle(isPhoneLayout: Bool) -> Font {
        display(isPhoneLayout ? .title : .largeTitle, weight: .black)
    }

    private static func interface(_ style: Font.TextStyle, weight: Font.Weight? = nil) -> Font {
        var font = Font.system(style)
        if let weight {
            font = font.weight(weight)
        }
        return font
    }

    private static func display(_ style: Font.TextStyle, weight: Font.Weight? = nil) -> Font {
        var font = Font.system(style, design: .rounded)
        if let weight {
            font = font.weight(weight)
        }
        return font
    }
}
