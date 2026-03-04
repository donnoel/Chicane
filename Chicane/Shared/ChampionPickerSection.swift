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
        VStack(alignment: .leading, spacing: 20) {
            Text(title)
                .font(.title3.weight(.semibold))
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
                    .fill(ChicaneTheme.insetFill(for: colorScheme))
            )
            .accessibilityLabel(title)
            .accessibilityHint("Select a \(participantSingular)")
        }
        .disabled(isDisabled)
    }
}
