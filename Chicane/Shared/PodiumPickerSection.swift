import SwiftUI

struct PodiumPickerSection: View {
    let title: String
    let drivers: [Driver]
    let participantSingular: String
    let participantPlural: String
    @Binding var draft: PodiumDraft
    var isDisabled = false

    init(
        title: String,
        drivers: [Driver],
        participantSingular: String = "driver",
        participantPlural: String = "drivers",
        draft: Binding<PodiumDraft>,
        isDisabled: Bool = false
    ) {
        self.title = title
        self.drivers = drivers
        self.participantSingular = participantSingular
        self.participantPlural = participantPlural
        _draft = draft
        self.isDisabled = isDisabled
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)

            positionPicker(title: "P1", position: 1, selection: $draft.p1)
            positionPicker(title: "P2", position: 2, selection: $draft.p2)
            positionPicker(title: "P3", position: 3, selection: $draft.p3)

            if draft.hasDuplicates {
                Text("Pick 3 unique \(participantPlural)")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(ChicaneTheme.f1Red)
                    .accessibilityLabel("Error: Pick 3 unique \(participantPlural)")
            }
        }
        .disabled(isDisabled)
    }

    private func positionPicker(
        title: String,
        position: Int,
        selection: Binding<String?>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.body.weight(.semibold))

            Picker(title, selection: selection) {
                Text("Choose \(participantSingular)")
                    .tag(Optional<String>.none)
                ForEach(drivers) { driver in
                    Text("\(driver.name) (\(driver.team))")
                        .tag(Optional(driver.id))
                        .disabled(draft.isSelectionDisabled(driverID: driver.id, for: position))
                }
            }
            .pickerStyle(.navigationLink)
            .padding(.horizontal, 12)
            .frame(minHeight: 48, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.1))
            )
            .accessibilityLabel("\(title) selection")
            .accessibilityHint("Select a \(participantSingular)")
        }
    }
}
