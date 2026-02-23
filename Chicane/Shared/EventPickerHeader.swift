import SwiftUI

/// Shared series + event picker header used by both PicksView and ResultsView.
///
/// Provides the title text, segmented series picker, and navigation-link event
/// picker in a consistent layout. Callers bind `selectedSeries` and
/// `selectedEventID` and pass the appropriate event list.
struct EventPickerHeader: View {
    let title: String
    @Binding var selectedSeries: RaceSeries
    @Binding var selectedEventID: String?
    let events: [RaceEvent]
    /// Accessibility label applied to the event picker (e.g. "Race event" or "Event result").
    var eventPickerLabel: String = "Race event"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
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
            .padding(.horizontal, 12)
            .frame(minHeight: 48)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.regularMaterial)
            )
            .accessibilityLabel(eventPickerLabel)
        }
    }
}

/// Shared event summary card used by both PicksView and ResultsView.
///
/// Shows title, series badge, round + circuit, and race date inside a glass card.
/// PicksView applies a slightly lighter secondary text colour; ResultsView uses
/// the standard `.secondary`. Pass `subtitleOpacity` to override.
struct EventSummaryCard: View {
    let event: RaceEvent
    /// Opacity for the round/circuit line. Picks uses `0.88` (on a dark glass card);
    /// Results uses `1.0` (standard `.secondary`).
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
                .font(.body)
                .foregroundStyle(
                    subtitleOpacity < 1.0
                    ? Color.white.opacity(subtitleOpacity)
                    : Color.secondary
                )
            Text(DateFormatter.dayMonthYear.string(from: event.raceDate))
                .font(.body)
        }
        .glassCard(accent: ChicaneTheme.seriesColor(event.series))
    }
}
