import SwiftUI

/// Shared series + event picker header used by both PicksView and ResultsView.
///
/// Provides the title text, segmented series picker, and navigation-link event
/// picker in a consistent layout. Callers bind `selectedSeries` and
/// `selectedEventID` and pass the appropriate event list.
struct EventPickerHeader: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    @Binding var selectedSeries: RaceSeries
    @Binding var selectedEventID: String?
    let events: [RaceEvent]
    /// Accessibility label applied to the event picker (e.g. "Race event" or "Event result").
    var eventPickerLabel: String = "Race event"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2.weight(.bold))

            Picker("Series", selection: $selectedSeries) {
                ForEach(RaceSeries.allCases) { series in
                    Text(series.title).tag(series)
                }
            }
            .pickerStyle(.segmented)
            .tint(ChicaneTheme.motoBlue)

            Picker("Event", selection: $selectedEventID) {
                Text("Choose event")
                    .tag(Optional<String>.none)
                ForEach(events) { event in
                    Text("R\(event.round) \(event.title)")
                        .tag(Optional(event.id))
                }
            }
            .tint(.primary)
            .padding(.horizontal, 12)
            .frame(minHeight: 48)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(ChicaneTheme.fieldFill(for: colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(ChicaneTheme.fieldStroke(for: colorScheme), lineWidth: 0.8)
                    )
            )
            .shadow(color: ChicaneTheme.fieldShadow(for: colorScheme), radius: 4, x: 0, y: 2)
            .accessibilityLabel(eventPickerLabel)
        }
        .padding(.bottom, 8)
    }
}

/// Shared event summary card used by both PicksView and ResultsView.
///
/// Shows title, series badge, round + circuit, and race date inside a glass card.
/// PicksView applies a slightly lighter secondary text colour; ResultsView uses
/// the standard `.secondary`. Pass `subtitleOpacity` to override.
struct EventSummaryCard: View {
    let event: RaceEvent
    /// Opacity for the round/circuit line.
    /// The subtitle always stays on the semantic secondary color so it remains
    /// readable in both light and dark mode.
    var subtitleOpacity: Double = 1.0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(event.title)
                    .font(.title3.weight(.semibold))
                Spacer()
                Text(event.series.shortTitle)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(ChicaneTheme.seriesColor(event.series), in: Capsule())
            }
            Text("Round \(event.round) · \(event.circuit)")
                .font(.subheadline)
                .foregroundStyle(Color.secondary.opacity(subtitleOpacity))
            TimelineView(.periodic(from: .now, by: 60)) { context in
                if let trackLocalTime = event.trackLocalTimeString(at: context.date) {
                    Label("Track now: \(trackLocalTime)", systemImage: "clock")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.secondary.opacity(subtitleOpacity))
                }
            }
            Text(DateFormatter.dayMonthYear.string(from: event.raceDate))
                .font(.subheadline)
        }
        .sectionCard(accent: ChicaneTheme.seriesColor(event.series))
    }
}
