import SwiftUI

struct PodiumPickerSection: View {
    @Environment(\.colorScheme) private var colorScheme

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
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)

            positionPicker(position: 1, selection: $draft.p1)
            positionPicker(position: 2, selection: $draft.p2)
            positionPicker(position: 3, selection: $draft.p3)

            if draft.hasDuplicates {
                Text("Pick 3 unique \(participantPlural)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ChicaneTheme.f1Red)
                    .accessibilityLabel("Error: Pick 3 unique \(participantPlural)")
            }
        }
        .disabled(isDisabled)
    }

    private func positionPicker(
        position: Int,
        selection: Binding<String?>
    ) -> some View {
        ZStack(alignment: .leading) {
            Picker(selection: selection) {
                Text("Choose \(participantSingular)")
                    .tag(Optional<String>.none)
                ForEach(drivers) { driver in
                    Text("\(driver.name) (\(driver.team))")
                        .tag(Optional(driver.id))
                        .disabled(draft.isSelectionDisabled(driverID: driver.id, for: position))
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.navigationLink)
            .tint(.primary)
            .padding(.leading, 58)
            .padding(.trailing, 12)
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
            .accessibilityLabel("Position \(position) selection")
            .accessibilityHint("Select a \(participantSingular)")

            PodiumMedalView(
                position: position,
                isSelected: selection.wrappedValue != nil
            )
            .padding(.leading, 12)
            .allowsHitTesting(false)
        }
    }
}
