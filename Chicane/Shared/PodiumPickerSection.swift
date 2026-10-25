import SwiftUI

struct PodiumPickerSection: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    positionNumber(position)
                    selectionField(position: position, selection: selection)
                }
            } else {
                HStack(spacing: 12) {
                    positionNumber(position)
                    Divider()
                        .frame(height: 26)
                        .accessibilityHidden(true)
                    selectionField(position: position, selection: selection)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(ChicaneTheme.fieldFill(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(ChicaneTheme.fieldStroke(for: colorScheme), lineWidth: 0.8)
                )
        )
    }

    private func positionNumber(_ position: Int) -> some View {
        Text(position.formatted(.number.precision(.integerLength(2))))
            .font(.system(.title, weight: .medium).monospacedDigit())
            .foregroundStyle(.primary)
            .fixedSize()
            .accessibilityHidden(true)
    }

    private func selectionField(position: Int, selection: Binding<String?>) -> some View {
        ParticipantSelectionField(
            title: "Position \(position) selection",
            drivers: drivers,
            participantSingular: participantSingular,
            disabledDriverIDs: disabledDriverIDs(for: position),
            selection: selection
        )
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
    }

    private func disabledDriverIDs(for position: Int) -> Set<String> {
        Set(drivers.map(\.id).filter { draft.isSelectionDisabled(driverID: $0, for: position) })
    }
}
