import SwiftUI

enum ChicaneTheme {
    static let f1Red = Color(red: 0.89, green: 0.08, blue: 0.13)
    static let motoBlue = Color(red: 0.15, green: 0.45, blue: 0.99)
    static let deepNavy = Color(red: 0.04, green: 0.08, blue: 0.18)
    static let dusk = Color(red: 0.11, green: 0.14, blue: 0.27)
    static let glowAmber = Color(red: 0.99, green: 0.61, blue: 0.28)
    static let midnight = Color(red: 0.02, green: 0.03, blue: 0.08)
    static let slate = Color(red: 0.08, green: 0.12, blue: 0.22)

    // Light gradient palette
    static let skyBlue    = Color(red: 0.76, green: 0.90, blue: 1.00)  // top – bright sky blue
    static let pearlBlue  = Color(red: 0.85, green: 0.92, blue: 1.00)  // mid – soft blue-white
    static let iceBlue    = Color(red: 0.93, green: 0.96, blue: 1.00)  // bottom – barely-there blue
    static let periwinkle = Color(red: 0.74, green: 0.76, blue: 1.00)  // accent orb – soft violet-blue
    static let seafoam    = Color(red: 0.58, green: 0.88, blue: 0.96)  // accent orb – light teal

    static var actionGradient: LinearGradient {
        LinearGradient(
            colors: [f1Red, motoBlue],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    static func seriesColor(_ series: RaceSeries) -> Color {
        switch series {
        case .formula1:
            return f1Red
        case .motoGP:
            return motoBlue
        }
    }

    static func scopeColor(_ scope: ScoreboardScope) -> Color {
        switch scope {
        case .formula1:
            return f1Red
        case .motoGP:
            return motoBlue
        case .combined:
            return glowAmber
        }
    }

    static func backgroundGradient(for colorScheme: ColorScheme) -> [Color] {
        switch colorScheme {
        case .dark:
            return [midnight, deepNavy, slate]
        default:
            return [skyBlue, pearlBlue, iceBlue]
        }
    }

    static func upperBloomColor(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            return f1Red.opacity(0.18)
        default:
            return periwinkle.opacity(0.28)
        }
    }

    static func lowerBloomColor(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            return motoBlue.opacity(0.20)
        default:
            return seafoam.opacity(0.22)
        }
    }

    static func highlightFill(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            return Color.white.opacity(0.08)
        default:
            return Color.white.opacity(0.20)
        }
    }

    static func cardSheen(for colorScheme: ColorScheme) -> [Color] {
        switch colorScheme {
        case .dark:
            return [
                Color.white.opacity(0.06),
                Color.white.opacity(0.02)
            ]
        default:
            return [
                Color.white.opacity(0.12),
                Color.white.opacity(0.03)
            ]
        }
    }

    static func insetFill(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            return Color.white.opacity(0.10)
        default:
            return Color.black.opacity(0.04)
        }
    }

    static func groupedFill(for colorScheme: ColorScheme, reduceTransparency: Bool = false) -> Color {
        if reduceTransparency {
            return Color(uiColor: .secondarySystemBackground)
        }
        switch colorScheme {
        case .dark:
            return Color.white.opacity(0.065)
        default:
            return Color.black.opacity(0.035)
        }
    }

    static func groupedStroke(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            return Color.white.opacity(0.09)
        default:
            return Color.black.opacity(0.035)
        }
    }

    static func sectionFill(for colorScheme: ColorScheme, reduceTransparency: Bool = false) -> AnyShapeStyle {
        if reduceTransparency {
            return AnyShapeStyle(Color(uiColor: .secondarySystemBackground))
        }
        switch colorScheme {
        case .dark:
            return AnyShapeStyle(Color.white.opacity(0.065))
        default:
            return AnyShapeStyle(Color.black.opacity(0.035))
        }
    }

    static func sectionStroke(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            return Color.white.opacity(0.09)
        default:
            return Color.black.opacity(0.035)
        }
    }

    static func fieldFill(for colorScheme: ColorScheme) -> AnyShapeStyle {
        switch colorScheme {
        case .dark:
            return AnyShapeStyle(Color.white.opacity(0.07))
        default:
            return AnyShapeStyle(Color.black.opacity(0.035))
        }
    }

    static func fieldStroke(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            return Color.white.opacity(0.09)
        default:
            return Color.black.opacity(0.04)
        }
    }

    static func fieldShadow(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            return Color.clear
        default:
            return Color.clear
        }
    }

    static func cardShadow(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            return Color.black.opacity(0.16)
        default:
            return Color.black.opacity(0.035)
        }
    }
}

// MARK: - Scroll offset tracking

/// Bubbles the scroll position of a ScrollView's content up through the
/// preference system so the background can react to it.
struct ScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

extension View {
    /// Attach this to the *content* VStack inside a ScrollView.
    /// It reads the VStack's minY in global space (which is 0 at rest and goes
    /// negative as the user scrolls down) and fires `onChange` with that value.
    func trackingScrollOffset(onChange: @escaping (CGFloat) -> Void) -> some View {
        self.background(
            GeometryReader { geo in
                Color.clear
                    .preference(
                        key: ScrollOffsetKey.self,
                        // minY is 0 at rest, negative when scrolled down.
                        // We negate it so callers receive positive values when scrolled down.
                        value: -geo.frame(in: .global).minY
                    )
            }
        )
        .onPreferenceChange(ScrollOffsetKey.self, perform: onChange)
    }
}

// MARK: - Parallax background

struct LiquidGlassBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    /// Current scroll position — positive = user has scrolled down.
    /// Each orb moves at a different fraction of this offset, creating depth.
    var scrollOffset: CGFloat = 0

    var body: some View {
        ZStack {
            // Base gradient — static, full bleed
            LinearGradient(
                colors: ChicaneTheme.backgroundGradient(for: colorScheme),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Periwinkle bloom — upper-right.
            // Moves at 0.18x scroll speed, drifting upward as content scrolls down.
            // Being furthest "back" in the scene it moves the least.
            Circle()
                .fill(ChicaneTheme.upperBloomColor(for: colorScheme))
                .frame(width: 320)
                .blur(radius: 78)
                .opacity(colorScheme == .dark ? 0.9 : 0.72)
                .offset(x: 155, y: -210 - scrollOffset * 0.10)

            // Seafoam bloom — lower-left.
            // Moves at 0.12x in the opposite vertical direction, increasing
            // the perceived separation between the two orbs as you scroll.
            Circle()
                .fill(ChicaneTheme.lowerBloomColor(for: colorScheme))
                .frame(width: 300)
                .blur(radius: 82)
                .opacity(colorScheme == .dark ? 0.9 : 0.7)
                .offset(x: -145, y: 280 + scrollOffset * 0.08)

            // White highlight capsule — centre.
            // Barely moves (0.06x) — it's the "closest" layer so has the
            // largest parallax but we keep it gentle so it stays centred.
            Capsule()
                .fill(ChicaneTheme.highlightFill(for: colorScheme))
                .frame(width: 280, height: 78)
                .blur(radius: 56)
                .offset(x: 12, y: 86 - scrollOffset * 0.04)
        }
    }
}

struct NeutralAppBackground: View {
    var body: some View {
        Color(uiColor: .systemBackground)
            .ignoresSafeArea()
    }
}

struct GlassCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    /// Accent is reserved for the stronger outline shown when the user asks to
    /// differentiate without color. Content carries the normal series identity.
    var accentColor: Color? = nil

    func body(content: Content) -> some View {
        let strokeColor = differentiateWithoutColor
            ? (accentColor ?? Color.primary).opacity(0.52)
            : Color.primary.opacity(colorScheme == .dark ? 0.09 : 0.035)

        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(strokeColor, lineWidth: differentiateWithoutColor ? 1.2 : 0.5)
            )
            .shadow(color: ChicaneTheme.cardShadow(for: colorScheme), radius: 8, x: 0, y: 3)
    }
}

struct GroupedCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    var accentColor: Color? = nil
    var tintColor: Color? = nil

    func body(content: Content) -> some View {
        let strokeColor: Color = if differentiateWithoutColor {
            Color.primary.opacity(0.42)
        } else if let tintColor {
            tintColor.opacity(colorScheme == .dark ? 0.30 : 0.20)
        } else {
            ChicaneTheme.groupedStroke(for: colorScheme)
        }

        let dashPattern: [CGFloat] = (differentiateWithoutColor && accentColor != nil) ? [6, 3] : []

        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(ChicaneTheme.groupedFill(for: colorScheme, reduceTransparency: reduceTransparency))
                    .overlay {
                        if let tintColor {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(tintColor.opacity(colorScheme == .dark ? 0.14 : 0.09))
                        }
                    }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        strokeColor,
                        style: StrokeStyle(
                            lineWidth: reduceTransparency ? 1.1 : 0.8,
                            dash: dashPattern
                        )
                    )
            )
    }
}

struct SectionCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    var accentColor: Color? = nil

    func body(content: Content) -> some View {
        let strokeColor = differentiateWithoutColor
            ? (accentColor ?? Color.primary).opacity(0.46)
            : ChicaneTheme.sectionStroke(for: colorScheme)

        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(ChicaneTheme.sectionFill(for: colorScheme, reduceTransparency: reduceTransparency))
            )
            .overlay(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        strokeColor,
                        lineWidth: differentiateWithoutColor || reduceTransparency ? 1.1 : 0.5
                    )
            }
    }
}

extension View {
    /// Plain glass card — neutral border, unchanged call sites work without modification.
    func glassCard() -> some View {
        modifier(GlassCardModifier())
    }

    /// Reactive glass card — border stroke animates to reflect `accent`.
    func glassCard(accent: Color) -> some View {
        modifier(GlassCardModifier(accentColor: accent))
    }

    func groupedCard() -> some View {
        modifier(GroupedCardModifier())
    }

    func groupedCard(accent: Color) -> some View {
        modifier(GroupedCardModifier(accentColor: accent))
    }

    func tintedGroupedCard(accent: Color) -> some View {
        modifier(GroupedCardModifier(accentColor: accent, tintColor: accent))
    }

    func sectionCard() -> some View {
        modifier(SectionCardModifier())
    }

    func sectionCard(accent: Color) -> some View {
        modifier(SectionCardModifier(accentColor: accent))
    }

    /// Applies the quiet adaptive canvas shared by the app's content screens.
    func chicaneBackground() -> some View {
        self
            .background(NeutralAppBackground())
    }

    /// Parallax variant — orbs drift at different rates relative to `scrollOffset`.
    /// Pass the value captured by `.trackingScrollOffset` on the scroll content.
    func chicaneBackground(scrollOffset: CGFloat) -> some View {
        self
            .background(NeutralAppBackground())
    }

    /// Hero-forward screens keep their branded feature card on the quiet canvas.
    func chicanePremiumBackground(scrollOffset: CGFloat = 0) -> some View {
        self
            .background(NeutralAppBackground())
    }
}

struct LargeActionButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Override the default F1-red→MotoGP-blue gradient with a solid tint.
    var tint: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        let opacity = configuration.isPressed ? 0.90 : 1.0
        let base = tint ?? .accentColor
        let fill = base.opacity(opacity)

        return configuration.label
            .font(ChicaneTypography.button)
            .frame(minHeight: 46)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(fill)
            )
            .foregroundStyle(.white)
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.98 : 1))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SecondaryActionButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var tint: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        let base = tint ?? .accentColor
        let backgroundOpacity = configuration.isPressed ? 0.13 : 0.08

        return configuration.label
            .font(ChicaneTypography.button)
            .frame(minHeight: 46)
            .frame(maxWidth: .infinity)
            .foregroundStyle(base)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(base.opacity(backgroundOpacity))
            )
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
