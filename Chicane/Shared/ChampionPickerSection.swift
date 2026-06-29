import SwiftUI

struct ChampionPickerSection: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let drivers: [Driver]
    let participantSingular: String
    @Binding var selection: String?
    var isDisabled = false

    init(
        title: String,
        drivers: [Driver],
        participantSingular: String = "driver",
        selection: Binding<String?>,
        isDisabled: Bool = false
    ) {
        self.title = title
        self.drivers = drivers
        self.participantSingular = participantSingular
        _selection = selection
        self.isDisabled = isDisabled
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(ChicaneTypography.sectionTitle)
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)

            Picker(title, selection: $selection) {
                Text("Choose \(participantSingular)")
                    .tag(Optional<String>.none)
                ForEach(drivers) { driver in
                    Text("\(driver.name) (\(driver.team))")
                        .tag(Optional(driver.id))
                }
            }
            .pickerStyle(.navigationLink)
            .tint(.primary)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(ChicaneTheme.fieldFill(for: colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(ChicaneTheme.fieldStroke(for: colorScheme), lineWidth: 0.8)
                    )
            )
            .shadow(color: ChicaneTheme.fieldShadow(for: colorScheme), radius: 4, x: 0, y: 2)
            .accessibilityIdentifier(title.isEmpty ? "ChampionSelection" : "ChampionPickSelection")
            .accessibilityLabel(title.isEmpty ? "Champion selection" : "\(title) selection")
            .accessibilityHint("Select a \(participantSingular)")
        }
        .disabled(isDisabled)
    }
}
