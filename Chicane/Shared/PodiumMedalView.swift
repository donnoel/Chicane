import SwiftUI

// MARK: - Podium Medal

/// Metallic circular medal for P1, P2, and P3 podium positions.
///
/// Built from three layers:
///  1. Angular gradient sweep — creates the rotating metallic sheen
///  2. Radial dome highlight — gives the circle a convex, 3-D appearance
///  3. Specular crescent — thin blurred white arc pinned to the top edge
///
/// When `isSelected` is true a coloured glow blooms behind the medal with
/// a spring animation, signalling that a driver has been assigned to this slot.
struct PodiumMedalView: View {
    let position: Int
    var isSelected: Bool = false

    var body: some View {
        ZStack {
            // Layer 1 — metallic angular sweep
            Circle()
                .fill(
                    AngularGradient(
                        colors: sweepColors,
                        center: .center,
                        startAngle: .degrees(-55),
                        endAngle: .degrees(305)
                    )
                )

            // Layer 2 — convex dome highlight (off-centre radial)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white.opacity(0.52), .clear],
                        center: UnitPoint(x: 0.36, y: 0.26),
                        startRadius: 0,
                        endRadius: 20
                    )
                )

            // Layer 3 — specular crescent at the top edge
            Ellipse()
                .fill(.white.opacity(0.38))
                .frame(width: 26, height: 9)
                .blur(radius: 2.5)
                .offset(y: -11)

            Text("\(position)")
                .font(ChicaneTypography.medalNumber)
                .foregroundStyle(numberColor)
                .shadow(color: .white.opacity(position == 2 ? 0.35 : 0.18), radius: 0.5, x: 0, y: 0.5)
                .offset(y: 0.5)
        }
        .frame(width: 38, height: 38)
        // Thin outer ring — white highlight fading to medal colour
        .overlay(
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.65), baseColor.opacity(0.35)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
        // Glow shadow — appears with a spring when a driver is selected
        .shadow(
            color: isSelected ? glowColor.opacity(0.50) : .clear,
            radius: isSelected ? 9 : 0,
            x: 0, y: 2
        )
        .animation(.spring(response: 0.30, dampingFraction: 0.78), value: isSelected)
    }

    // MARK: - Colour definitions

    /// The angular sweep palette that forms the metallic base.
    private var sweepColors: [Color] {
        switch position {
        case 1: // Gold
            return [
                Color(red: 0.68, green: 0.48, blue: 0.02),   // deep amber
                Color(red: 1.00, green: 0.85, blue: 0.28),   // bright gold
                Color(red: 0.98, green: 0.97, blue: 0.74),   // pale champagne
                Color(red: 1.00, green: 0.85, blue: 0.28),   // bright gold
                Color(red: 0.68, green: 0.48, blue: 0.02),   // deep amber
            ]
        case 2: // Silver
            return [
                Color(red: 0.42, green: 0.42, blue: 0.46),   // dark steel
                Color(red: 0.80, green: 0.82, blue: 0.86),   // mid silver
                Color(red: 0.96, green: 0.96, blue: 0.98),   // near-white
                Color(red: 0.80, green: 0.82, blue: 0.86),   // mid silver
                Color(red: 0.42, green: 0.42, blue: 0.46),   // dark steel
            ]
        default: // Bronze (P3 and beyond)
            return [
                Color(red: 0.52, green: 0.25, blue: 0.06),   // dark bronze
                Color(red: 0.78, green: 0.49, blue: 0.19),   // warm copper
                Color(red: 0.92, green: 0.72, blue: 0.52),   // pale brass
                Color(red: 0.78, green: 0.49, blue: 0.19),   // warm copper
                Color(red: 0.52, green: 0.25, blue: 0.06),   // dark bronze
            ]
        }
    }

    /// Representative mid-tone used for the outer ring gradient end stop.
    private var baseColor: Color {
        switch position {
        case 1: return Color(red: 1.00, green: 0.85, blue: 0.28)
        case 2: return Color(red: 0.80, green: 0.82, blue: 0.86)
        default: return Color(red: 0.78, green: 0.49, blue: 0.19)
        }
    }

    private var numberColor: Color {
        switch position {
        case 1:
            return Color.black.opacity(0.78)
        case 2:
            return Color.black.opacity(0.72)
        default:
            return Color.white.opacity(0.94)
        }
    }

    /// Colour used for the selection glow shadow.
    private var glowColor: Color {
        switch position {
        case 1: return Color(red: 1.00, green: 0.80, blue: 0.10) // warm gold
        case 2: return Color(red: 0.72, green: 0.78, blue: 0.96) // cool silver-blue
        default: return Color(red: 0.78, green: 0.49, blue: 0.19) // copper
        }
    }
}
