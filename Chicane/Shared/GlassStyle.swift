import SwiftUI

enum ChicaneTheme {
    static let f1Red = Color(red: 0.89, green: 0.08, blue: 0.13)
    static let motoBlue = Color(red: 0.15, green: 0.45, blue: 0.99)
    static let deepNavy = Color(red: 0.04, green: 0.08, blue: 0.18)
    static let dusk = Color(red: 0.11, green: 0.14, blue: 0.27)
    static let glowAmber = Color(red: 0.99, green: 0.61, blue: 0.28)

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
    /// Current scroll position — positive = user has scrolled down.
    /// Each orb moves at a different fraction of this offset, creating depth.
    var scrollOffset: CGFloat = 0

    var body: some View {
        ZStack {
            // Base gradient — static, full bleed
            LinearGradient(
                colors: [ChicaneTheme.skyBlue, ChicaneTheme.pearlBlue, ChicaneTheme.iceBlue],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Periwinkle bloom — upper-right.
            // Moves at 0.18x scroll speed, drifting upward as content scrolls down.
            // Being furthest "back" in the scene it moves the least.
            Circle()
                .fill(ChicaneTheme.periwinkle.opacity(0.28))
                .frame(width: 360)
                .blur(radius: 90)
                .offset(x: 170, y: -230 - scrollOffset * 0.18)

            // Seafoam bloom — lower-left.
            // Moves at 0.12x in the opposite vertical direction, increasing
            // the perceived separation between the two orbs as you scroll.
            Circle()
                .fill(ChicaneTheme.seafoam.opacity(0.22))
                .frame(width: 340)
                .blur(radius: 95)
                .offset(x: -160, y: 300 + scrollOffset * 0.12)

            // White highlight capsule — centre.
            // Barely moves (0.06x) — it's the "closest" layer so has the
            // largest parallax but we keep it gentle so it stays centred.
            Capsule()
                .fill(Color.white.opacity(0.30))
                .frame(width: 320, height: 90)
                .blur(radius: 70)
                .offset(x: 20, y: 80 - scrollOffset * 0.06)
        }
    }
}

struct GlassCardModifier: ViewModifier {
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
                accent.opacity(0.70),
                accent.opacity(0.38),
                Color.white.opacity(0.18)
            ]
        } else {
            return [
                Color.primary.opacity(0.35),
                ChicaneTheme.motoBlue.opacity(0.22),
                ChicaneTheme.f1Red.opacity(0.22)
            ]
        }
    }

    func body(content: Content) -> some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.18),
                                        Color.white.opacity(0.02)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: strokeColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                    // Smooth spring transition whenever accentColor changes
                    .animation(.spring(response: 0.45, dampingFraction: 0.85), value: accentColor)
            )
            .shadow(color: Color.black.opacity(0.22), radius: 16, x: 0, y: 8)
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

    /// Applies the shared light-blue gradient behind any view, hiding the
    /// system navigation-bar tint so the gradient shows through edge-to-edge.
    func chicaneBackground() -> some View {
        self
            .background(LiquidGlassBackground().ignoresSafeArea())
            .toolbarBackground(.hidden, for: .navigationBar)
    }

    /// Parallax variant — orbs drift at different rates relative to `scrollOffset`.
    /// Pass the value captured by `.trackingScrollOffset` on the scroll content.
    func chicaneBackground(scrollOffset: CGFloat) -> some View {
        self
            .background(LiquidGlassBackground(scrollOffset: scrollOffset).ignoresSafeArea())
            .toolbarBackground(.hidden, for: .navigationBar)
    }
}

struct LargeActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.horizontal, 18)
            .frame(minHeight: 48)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: configuration.isPressed
                                ? [ChicaneTheme.f1Red.opacity(0.88), ChicaneTheme.motoBlue.opacity(0.88)]
                                : [ChicaneTheme.f1Red, ChicaneTheme.motoBlue],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
            .foregroundStyle(.white)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .shadow(color: ChicaneTheme.motoBlue.opacity(0.35), radius: 8, x: 0, y: 4)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Loading overlay

/// A subtle full-screen overlay shown while the app is loading data.
/// Applied once at the `RootTabView` level so all tabs share a single indicator.
struct LoadingOverlayModifier: ViewModifier {
    let isLoading: Bool

    func body(content: Content) -> some View {
        content
            .overlay {
                if isLoading {
                    ZStack {
                        Color.black.opacity(0.25)
                            .ignoresSafeArea()
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                            .scaleEffect(1.4)
                            .padding(24)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                    .accessibilityLabel("Loading")
                }
            }
    }
}

extension View {
    func loadingOverlay(isLoading: Bool) -> some View {
        modifier(LoadingOverlayModifier(isLoading: isLoading))
    }
}
