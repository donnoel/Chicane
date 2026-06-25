import SwiftUI

/// A score display that counts up from zero to `value` on first appearance,
/// and rolls to a new total whenever the value changes.
///
/// Internally animates a `Double` so SwiftUI interpolates smoothly on every
/// frame; the displayed integer therefore increments one-by-one rather than
/// hard-cutting. `.contentTransition(.numericText)` makes each digit roll in
/// the correct direction — up when the score increases, down when it drops.
///
/// Usage:
/// ```swift
/// AnimatedScoreText(value: standing.points)
///     .font(.title3.weight(.bold))
/// ```
struct AnimatedScoreText: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let value: Int

    /// A short entry delay (seconds) before the count-up begins on first
    /// appearance — gives the card time to settle into position.
    var entryDelay: Double = 0.12

    @State private var displayed: Double = 0
    @State private var appeared = false

    var body: some View {
        scoreText
            .onAppear {
                guard !appeared else { return }
                appeared = true
                guard !reduceMotion else {
                    displayed = Double(value)
                    return
                }
                // Count up from zero when the view first enters the hierarchy.
                DispatchQueue.main.asyncAfter(deadline: .now() + entryDelay) {
                    displayed = Double(value)
                }
            }
            .onChange(of: value) { _, newValue in
                // Roll to updated total whenever scores change.
                displayed = Double(newValue)
            }
    }

    @ViewBuilder
    private var scoreText: some View {
        if reduceMotion {
            Text("\(value)")
                .monospacedDigit()
        } else {
            Text("\(Int(displayed.rounded()))")
                .monospacedDigit()
                .contentTransition(.numericText(value: displayed))
                .animation(
                    .spring(response: 0.62, dampingFraction: 0.78),
                    value: displayed
                )
        }
    }
}
