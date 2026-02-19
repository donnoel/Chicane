import SwiftUI

struct PodiumPickerSection: View {
    let title: String
    let drivers: [Driver]
    @Binding var draft: PodiumDraft
    var isDisabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)

            positionPicker(title: "P1", position: 1, selection: $draft.p1)
            positionPicker(title: "P2", position: 2, selection: $draft.p2)
            positionPicker(title: "P3", position: 3, selection: $draft.p3)

            if draft.hasDuplicates {
                Text("Pick 3 unique drivers")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.red)
                    .accessibilityLabel("Error: Pick 3 unique drivers")
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
                Text("Choose driver")
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
                    .fill(Color.primary.opacity(0.05))
            )
            .accessibilityLabel("\(title) selection")
            .accessibilityHint("Select a driver")
        }
    }
}
