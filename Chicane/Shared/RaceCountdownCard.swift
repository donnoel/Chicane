import SwiftUI

// MARK: - Race Countdown Card

/// Live countdown card for the next upcoming race.
///
/// Uses an adaptive `TimelineView` cadence:
/// - per-minute while the race is 24+ hours away
/// - per-second inside the final 24 hours (when seconds are shown)
/// Within 72 hours of race start the pills turn the series colour and the card
/// gains a coloured glow.
struct RaceCountdownCard: View {
    private enum Constants {
        static let countdownSecondsWindow: TimeInterval = 24 * 3600
    }

    let event: RaceEvent

    private var seriesColor: Color { ChicaneTheme.seriesColor(event.series) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { minuteContext in
            let minuteRemaining = event.raceDate.timeIntervalSince(minuteContext.date)
            if minuteRemaining > 0 && minuteRemaining < Constants.countdownSecondsWindow {
                TimelineView(.periodic(from: minuteContext.date, by: 1)) { secondContext in
                    countdownContent(now: secondContext.date)
                }
            } else {
                countdownContent(now: minuteContext.date)
            }
        }
    }

    @ViewBuilder
    private func countdownContent(now: Date) -> some View {
        let remaining = event.raceDate.timeIntervalSince(now)
        let isRaceWeekend = remaining > 0 && remaining < 3 * 24 * 3600

        cardContent(remaining: remaining, isRaceWeekend: isRaceWeekend, now: now)
            .glassCard(accent: seriesColor)
            // Coloured glow that fades in as race weekend approaches
            .shadow(
                color: isRaceWeekend ? seriesColor.opacity(0.16) : .clear,
                radius: isRaceWeekend ? 12 : 0,
                x: 0, y: 4
            )
            .animation(.easeInOut(duration: 0.8), value: isRaceWeekend)
    }

    // MARK: Card body

    @ViewBuilder
    private func cardContent(remaining: TimeInterval, isRaceWeekend: Bool, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 16) {

            // Header row with label + series badge
            HStack {
                Label("Next Race", systemImage: "calendar")
                    .font(ChicaneTypography.cardTitle)
                Spacer()
                Text(event.series.shortTitle)
                    .font(ChicaneTypography.captionSemibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(seriesColor, in: Capsule())
            }

            // Race name and circuit
            Text(event.title)
                .font(ChicaneTypography.screenTitle)
            Text(event.circuit)
                .font(ChicaneTypography.subtitle)
                .foregroundStyle(.secondary)
            if let trackLocalTime = event.trackLocalTimeString(at: now) {
                Label("Track now: \(trackLocalTime)", systemImage: "clock")
                    .font(ChicaneTypography.footnoteSemibold)
                    .foregroundStyle(.secondary)
            }

            // Live countdown vs. post-race state
            if remaining > 0 {
                countdownPills(remaining: remaining, isRaceWeekend: isRaceWeekend)
            } else {
                raceCompleteRow
            }
        }
    }

    // MARK: Countdown pills

    @ViewBuilder
    private func countdownPills(remaining: TimeInterval, isRaceWeekend: Bool) -> some View {
        let showSeconds = remaining < 24 * 3600

        let days    = Int(remaining) / 86400
        let hours   = (Int(remaining) % 86400) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        let seconds = Int(remaining) % 60

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                if !showSeconds {
                    CountdownUnitView(
                        value: days,
                        label: "DAYS",
                        accentColor: isRaceWeekend ? seriesColor : nil
                    )
                }
                CountdownUnitView(
                    value: hours,
                    label: "HRS",
                    accentColor: isRaceWeekend ? seriesColor : nil
                )
                CountdownUnitView(
                    value: minutes,
                    label: "MIN",
                    accentColor: isRaceWeekend ? seriesColor : nil
                )
                if showSeconds {
                    CountdownUnitView(
                        value: seconds,
                        label: "SEC",
                        accentColor: isRaceWeekend ? seriesColor : nil
                    )
                }
            }

            // Date string or pulsing race-weekend indicator
            if isRaceWeekend {
                RaceWeekendBadge(color: seriesColor)
            } else {
                Text(DateFormatter.dayMonthYear.string(from: event.raceDate))
                    .font(ChicaneTypography.subtitle)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Supporting rows

    private var raceCompleteRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "flag.checkered")
                .foregroundStyle(seriesColor)
            Text("Race complete")
                .font(ChicaneTypography.bodySemibold)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Countdown Unit Pill

/// A single glass pill showing a two-digit value and a short label below.
/// Tinted with `accentColor` during race weekend; neutral otherwise.
struct CountdownUnitView: View {
    @Environment(\.colorScheme) private var colorScheme

    let value: Int
    let label: String
    var accentColor: Color?

    var body: some View {
        VStack(spacing: 4) {
            Text(String(format: "%02d", value))
                .font(ChicaneTypography.countdownNumber)
                .foregroundStyle(accentColor ?? .primary)
                // Smooth digit roll on every tick
                .contentTransition(.numericText(countsDown: true))
                .animation(.spring(response: 0.35, dampingFraction: 0.75), value: value)
                .frame(minWidth: 56)
                .padding(.vertical, 10)
                .padding(.horizontal, 4)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(ChicaneTheme.fieldFill(for: colorScheme))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(accentColor?.opacity(0.34) ?? ChicaneTheme.fieldStroke(for: colorScheme), lineWidth: 0.8)
                        }
                }
                // Soft coloured glow behind each pill when active
                .shadow(color: accentColor?.opacity(0.18) ?? ChicaneTheme.fieldShadow(for: colorScheme), radius: 6, x: 0, y: 3)

            Text(label)
                .font(ChicaneTypography.countdownLabel)
                .tracking(0.8)
                .foregroundStyle(accentColor?.opacity(0.8) ?? .secondary)
        }
    }
}

// MARK: - Race Weekend Badge

/// Pulsing dot + "Race weekend" label shown when within 72 h of race start.
private struct RaceWeekendBadge: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let color: Color
    @State private var pulsing = false

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .scaleEffect(pulsing ? 1.35 : 1.0)
                .opacity(pulsing ? 0.55 : 1.0)
                .animation(
                    reduceMotion ? .none : .easeInOut(duration: 0.85).repeatForever(autoreverses: true),
                    value: pulsing
                )
                .onAppear { pulsing = true }

            Text("Race weekend")
                .font(ChicaneTypography.captionSemibold)
                .foregroundStyle(color)
        }
    }
}
