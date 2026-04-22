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
            return Color(uiColor: colorScheme == .dark ? .secondarySystemBackground : .systemBackground)
        }
        switch colorScheme {
        case .dark:
            return Color.white.opacity(0.10)
        default:
            return Color.white.opacity(0.88)
        }
    }

    static func groupedStroke(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            return Color.white.opacity(0.10)
        default:
            return Color.black.opacity(0.06)
        }
    }

    static func sectionFill(for colorScheme: ColorScheme, reduceTransparency: Bool = false) -> AnyShapeStyle {
        if reduceTransparency {
            return AnyShapeStyle(Color(uiColor: colorScheme == .dark ? .secondarySystemBackground : .systemBackground))
        }
        switch colorScheme {
        case .dark:
            return AnyShapeStyle(.regularMaterial)
        default:
            return AnyShapeStyle(Color.white.opacity(0.78))
        }
    }

    static func sectionStroke(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            return Color.white.opacity(0.10)
        default:
            return Color.white.opacity(0.72)
        }
    }

    static func fieldFill(for colorScheme: ColorScheme) -> AnyShapeStyle {
        switch colorScheme {
        case .dark:
            return AnyShapeStyle(Color.white.opacity(0.12))
        default:
            return AnyShapeStyle(Color.white.opacity(0.94))
        }
    }

    static func fieldStroke(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            return Color.white.opacity(0.08)
        default:
            return Color.black.opacity(0.05)
        }
    }

    static func fieldShadow(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            return Color.black.opacity(0.10)
        default:
            return Color.black.opacity(0.06)
        }
    }

    static func cardShadow(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            return Color.black.opacity(0.24)
        default:
            return Color.black.opacity(0.09)
        }
    }
}

// MARK: - Scroll offset tracking

/// Bubbles the scroll position of a ScrollView's content up through the
/// preference system so the background can react to it.
struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
            Circle()
                .fill(ChicaneTheme.motoBlue.opacity(colorScheme == .dark ? 0.10 : 0.08))
                .frame(width: 360, height: 360)
                .blur(radius: 90)
                .offset(x: 180, y: -250)

            Circle()
                .fill(ChicaneTheme.f1Red.opacity(colorScheme == .dark ? 0.08 : 0.05))
                .frame(width: 300, height: 300)
                .blur(radius: 90)
                .offset(x: -180, y: -320)

            LinearGradient(
                colors: [
                    Color(uiColor: colorScheme == .dark ? .secondarySystemBackground : .systemBackground).opacity(0.55),
                    Color.clear,
                    Color(uiColor: .systemGroupedBackground).opacity(0.35)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

struct GlassCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// When non-nil the border stroke animates to reflect this colour —
    /// e.g. the active series (F1 red / MotoGP blue) or scope (amber).
    /// Pass `nil` (the default) to keep the neutral static border.
    var accentColor: Color? = nil

    /// Stroke gradient colours derived from the current accent.
    /// Expressed as a computed property so SwiftUI diffs them on every render
    /// and the `.animation` on the overlay handles the interpolation.
    private var strokeColors: [Color] {
        if let accent = accentColor {
            return [
                accent.opacity(0.45),
                accent.opacity(0.24),
                colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.10)
            ]
        } else {
            return [
                Color.primary.opacity(0.15),
                ChicaneTheme.motoBlue.opacity(0.10),
                ChicaneTheme.f1Red.opacity(0.10)
            ]
        }
    }

    private var cardFill: AnyShapeStyle {
        if reduceTransparency {
            return AnyShapeStyle(Color(uiColor: colorScheme == .dark ? .secondarySystemBackground : .systemBackground))
        }
        return AnyShapeStyle(.thinMaterial)
    }

    func body(content: Content) -> some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(cardFill)
                    .overlay {
                        if !reduceTransparency {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: ChicaneTheme.cardSheen(for: colorScheme),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                    }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: strokeColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: reduceTransparency ? 1.1 : 0.8
                    )
                    // Smooth spring transition whenever accentColor changes
                    .animation(.spring(response: 0.45, dampingFraction: 0.85), value: accentColor)
            )
            .shadow(color: ChicaneTheme.cardShadow(for: colorScheme), radius: 8, x: 0, y: 4)
    }
}

struct GroupedCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    var accentColor: Color? = nil

    func body(content: Content) -> some View {
        let strokeColor: Color = if differentiateWithoutColor {
            Color.primary.opacity(0.42)
        } else {
            (accentColor ?? ChicaneTheme.groupedStroke(for: colorScheme)).opacity(0.32)
        }

        let dashPattern: [CGFloat] = (differentiateWithoutColor && accentColor != nil) ? [6, 3] : []

        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(ChicaneTheme.groupedFill(for: colorScheme, reduceTransparency: reduceTransparency))
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

    func body(content: Content) -> some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(ChicaneTheme.sectionFill(for: colorScheme, reduceTransparency: reduceTransparency))
            )
            .overlay(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        ChicaneTheme.sectionStroke(for: colorScheme),
                        lineWidth: reduceTransparency ? 1.1 : 0.8
                    )
            }
            .shadow(color: ChicaneTheme.cardShadow(for: colorScheme), radius: 10, x: 0, y: 6)
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

    func sectionCard() -> some View {
        modifier(SectionCardModifier())
    }

    func sectionCard(accent: Color) -> some View {
        modifier(SectionCardModifier())
    }

    /// Applies the shared light-blue gradient behind any view, hiding the
    /// system navigation-bar tint so the gradient shows through edge-to-edge.
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

    /// Premium branded backdrop for hero-forward screens.
    func chicanePremiumBackground(scrollOffset: CGFloat = 0) -> some View {
        self
            .background(LiquidGlassBackground(scrollOffset: scrollOffset).ignoresSafeArea())
            .toolbarBackground(.hidden, for: .navigationBar)
    }
}

struct LargeActionButtonStyle: ButtonStyle {
    /// Override the default F1-red→MotoGP-blue gradient with a solid tint.
    var tint: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        let opacity = configuration.isPressed ? 0.90 : 1.0
        let fill: AnyShapeStyle = if let tint {
            AnyShapeStyle(tint.opacity(opacity))
        } else {
            AnyShapeStyle(LinearGradient(
                colors: [ChicaneTheme.f1Red.opacity(0.90 * opacity), ChicaneTheme.motoBlue.opacity(0.90 * opacity)],
                startPoint: .leading,
                endPoint: .trailing
            ))
        }

        return configuration.label
            .font(.subheadline.weight(.semibold))
            .frame(minHeight: 46)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(fill)
            )
            .foregroundStyle(.white)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .shadow(color: (tint ?? ChicaneTheme.motoBlue).opacity(0.18), radius: 4, x: 0, y: 2)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SecondaryActionButtonStyle: ButtonStyle {
    var tint: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        let base = tint ?? .accentColor
        let backgroundOpacity = configuration.isPressed ? 0.16 : 0.12

        return configuration.label
            .font(.subheadline.weight(.semibold))
            .frame(minHeight: 46)
            .frame(maxWidth: .infinity)
            .foregroundStyle(base)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(base.opacity(backgroundOpacity))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(base.opacity(0.28), lineWidth: 1)
            )
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
