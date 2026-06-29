import SwiftUI

struct ParticipantSelectionField: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let title: String
    let drivers: [Driver]
    let participantSingular: String
    let disabledDriverIDs: Set<String>
    @Binding var selection: String?
    @State private var isPickerPresented = false

    init(
        title: String,
        drivers: [Driver],
        participantSingular: String,
        disabledDriverIDs: Set<String> = [],
        selection: Binding<String?>
    ) {
        self.title = title
        self.drivers = drivers
        self.participantSingular = participantSingular
        self.disabledDriverIDs = disabledDriverIDs
        _selection = selection
    }

    var body: some View {
        Button {
            isPickerPresented = true
        } label: {
            HStack(spacing: 12) {
                Text(selectionLabel)
                    .lineLimit(1)
                    .foregroundStyle(selection == nil ? .secondary : .primary)
                Spacer(minLength: 8)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(selectionLabel)
        .accessibilityHint("Select a \(participantSingular)")
        .fullScreenCover(isPresented: compactPresentationIsPresented) {
            pickerList
        }
        .sheet(isPresented: regularPresentationIsPresented) {
            pickerList
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private var compactPresentationIsPresented: Binding<Bool> {
        Binding(
            get: { isPickerPresented && horizontalSizeClass != .regular },
            set: { isPresented in
                if !isPresented {
                    isPickerPresented = false
                }
            }
        )
    }

    private var regularPresentationIsPresented: Binding<Bool> {
        Binding(
            get: { isPickerPresented && horizontalSizeClass == .regular },
            set: { isPresented in
                if !isPresented {
                    isPickerPresented = false
                }
            }
        )
    }

    private var selectionLabel: String {
        guard let selection, let driver = drivers.first(where: { $0.id == selection }) else {
            return "Choose \(participantSingular)"
        }
        return "\(driver.name) (\(driver.team))"
    }

    private var pickerList: some View {
        NavigationStack {
            List {
                Button {
                    selection = nil
                    isPickerPresented = false
                } label: {
                    selectionRow(title: "Choose \(participantSingular)", isSelected: selection == nil)
                }

                ForEach(drivers) { driver in
                    Button {
                        selection = driver.id
                        isPickerPresented = false
                    } label: {
                        selectionRow(
                            title: "\(driver.name) (\(driver.team))",
                            isSelected: selection == driver.id
                        )
                    }
                    .disabled(disabledDriverIDs.contains(driver.id))
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPickerPresented = false
                    }
                }
            }
        }
    }

    private func selectionRow(title: String, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .foregroundStyle(.primary)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
            }
        }
    }
}
