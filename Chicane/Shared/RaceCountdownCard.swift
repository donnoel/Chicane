import SwiftUI

// MARK: - Race Countdown Card

/// Live countdown card for the next upcoming race.
///
/// Uses `TimelineView` to tick every second. Within 72 hours of race start the
/// pills turn the series colour and the card gains a coloured glow. Inside 24
/// hours the display switches from DAYS/HRS/MIN to HRS/MIN/SEC for urgency.
struct RaceCountdownCard: View {
    let event: RaceEvent

    private var seriesColor: Color { ChicaneTheme.seriesColor(event.series) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining     = event.raceDate.timeIntervalSince(context.date)
            let isRaceWeekend = remaining > 0 && remaining < 3 * 24 * 3600

            cardContent(remaining: remaining, isRaceWeekend: isRaceWeekend)
                .glassCard(accent: seriesColor)
                // Coloured glow that fades in as race weekend approaches
                .shadow(
                    color: isRaceWeekend ? seriesColor.opacity(0.45) : .clear,
                    radius: isRaceWeekend ? 26 : 0,
                    x: 0, y: 8
                )
                .animation(.easeInOut(duration: 0.8), value: isRaceWeekend)
        }
    }

    // MARK: Card body

    @ViewBuilder
    private func cardContent(remaining: TimeInterval, isRaceWeekend: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {

            // Header row with label + series badge
            HStack {
                Label("Next race", systemImage: "calendar")
                    .font(.headline)
                Spacer()
                Text(event.series.shortTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(seriesColor, in: Capsule())
            }

            // Race name and circuit
            Text(event.title)
                .font(.title2.weight(.semibold))
            Text(event.circuit)
                .font(.body)
                .foregroundStyle(.secondary)

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

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
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
                    .font(.body)
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
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Countdown Unit Pill

/// A single glass pill showing a two-digit value and a short label below.
/// Tinted with `accentColor` during race weekend; neutral otherwise.
struct CountdownUnitView: View {
    let value: Int
    let label: String
    var accentColor: Color?

    var body: some View {
        VStack(spacing: 4) {
            Text(String(format: "%02d", value))
                .font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(accentColor ?? .primary)
                // Smooth digit roll on every tick
                .contentTransition(.numericText(countsDown: true))
                .animation(.spring(response: 0.35, dampingFraction: 0.75), value: value)
                .frame(minWidth: 56)
                .padding(.vertical, 10)
                .padding(.horizontal, 4)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            // Specular highlight on the top edge
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [.white.opacity(0.22), .clear],
                                        startPoint: .top,
                                        endPoint: .center
                                    )
                                )
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(
                                    accentColor?.opacity(0.35) ?? Color.primary.opacity(0.12),
                                    lineWidth: 1
                                )
                        }
                }
                // Soft coloured glow behind each pill when active
                .shadow(color: accentColor?.opacity(0.22) ?? .clear, radius: 8, x: 0, y: 2)

            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(accentColor?.opacity(0.8) ?? .secondary)
        }
    }
}

// MARK: - Race Weekend Badge

/// Pulsing dot + "Race weekend" label shown when within 72 h of race start.
private struct RaceWeekendBadge: View {
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
                    .easeInOut(duration: 0.85).repeatForever(autoreverses: true),
                    value: pulsing
                )
                .onAppear { pulsing = true }

            Text("Race weekend")
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
        }
    }
}
