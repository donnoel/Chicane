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
            if !title.isEmpty {
                Text(title)
                    .font(ChicaneTypography.sectionTitle)
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
            }

            positionPicker(position: 1, selection: $draft.p1)
            positionPicker(position: 2, selection: $draft.p2)
            positionPicker(position: 3, selection: $draft.p3)

            if draft.hasDuplicates {
                Text("Pick 3 unique \(participantPlural)")
                    .font(ChicaneTypography.sectionTitle)
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
            ParticipantSelectionField(
                title: "Position \(position) selection",
                drivers: drivers,
                participantSingular: participantSingular,
                disabledDriverIDs: disabledDriverIDs(for: position),
                selection: selection
            )
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

    private func disabledDriverIDs(for position: Int) -> Set<String> {
        Set(drivers.map(\.id).filter { draft.isSelectionDisabled(driverID: $0, for: position) })
    }
}
