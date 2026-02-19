import SwiftUI

enum ChicaneTheme {
    static let f1Red = Color(red: 0.89, green: 0.08, blue: 0.13)
    static let motoBlue = Color(red: 0.15, green: 0.45, blue: 0.99)
    static let deepNavy = Color(red: 0.04, green: 0.08, blue: 0.18)
    static let dusk = Color(red: 0.11, green: 0.14, blue: 0.27)
    static let glowAmber = Color(red: 0.99, green: 0.61, blue: 0.28)

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

struct LiquidGlassBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [ChicaneTheme.deepNavy, ChicaneTheme.dusk, Color.black.opacity(0.88)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(ChicaneTheme.f1Red.opacity(0.36))
                .frame(width: 340)
                .blur(radius: 95)
                .offset(x: -170, y: -250)

            Circle()
                .fill(ChicaneTheme.motoBlue.opacity(0.33))
                .frame(width: 380)
                .blur(radius: 100)
                .offset(x: 180, y: 280)

            Capsule()
                .fill(Color.white.opacity(0.12))
                .frame(width: 360, height: 110)
                .blur(radius: 85)
                .offset(x: 0, y: 340)
        }
    }
}

struct GlassCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
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
                            colors: [
                                Color.white.opacity(0.55),
                                ChicaneTheme.motoBlue.opacity(0.22),
                                ChicaneTheme.f1Red.opacity(0.22)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.22), radius: 16, x: 0, y: 8)
    }
}

extension View {
    func glassCard() -> some View {
        modifier(GlassCardModifier())
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
