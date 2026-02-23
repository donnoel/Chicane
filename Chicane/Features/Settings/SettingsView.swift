import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    @State private var playerNames: [UUID: String] = [:]
    @State private var newPlayerName = ""
    @State private var seasonBetText = ""
    @State private var showResetConfirmation = false

    private enum FocusField: Hashable {
        case player(UUID)
        case newPlayer
        case seasonBet
    }

    @FocusState private var focusedField: FocusField?

    var body: some View {
        Form {
            playerSection
            spoilerSection
            betSection
            resetSection
        }
        .tint(.accentColor)
        .scrollContentBackground(.hidden)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .chicaneBackground()
        .task {
            hydrateLocalState()
        }
        .onChange(of: viewModel.players) {
            hydrateLocalState()
        }
        .onChange(of: viewModel.settings) {
            hydrateLocalState()
        }
        .alert("Reset season?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                Task {
                    await resetSeason()
                }
            }
        } message: {
            Text("This clears all picks and results for the season.")
        }
    }

    private var playerSection: some View {
        Section("Players") {
            ForEach(viewModel.players) { player in
                HStack(spacing: 10) {
                    TextField("Player name", text: binding(for: player.id))
                        .textInputAutocapitalization(.words)
                        .disableAutocorrection(true)
                        .focused($focusedField, equals: .player(player.id))
                        .accessibilityLabel("Name for \(player.name)")

                    if viewModel.players.count > 1 {
                        Button("Remove", role: .destructive) {
                            Task {
                                await removePlayer(playerID: player.id)
                            }
                        }
                        .buttonStyle(.bordered)
                        .frame(minHeight: 44)
                    }
                }
            }

            Button("Save player names") {
                Task {
                    await savePlayerNames()
                }
            }
            .buttonStyle(.borderedProminent)
            .frame(minHeight: 44)

            HStack(spacing: 10) {
                TextField("Add player", text: $newPlayerName)
                    .textInputAutocapitalization(.words)
                    .disableAutocorrection(true)
                    .focused($focusedField, equals: .newPlayer)
                    .onSubmit {
                        Task { await addPlayer() }
                    }
                Button("Add") {
                    Task {
                        await addPlayer()
                    }
                }
                .buttonStyle(.borderedProminent)
                .frame(minHeight: 44)
            }
        }
    }

    private var spoilerSection: some View {
        Section("Spoilers") {
            Toggle("Require spoiler confirmation", isOn: spoilerGateBinding)
                .accessibilityHint("Shows a warning before opening spoilers")

            Toggle("Show Spoilers tab", isOn: spoilersSectionBinding)
                .accessibilityHint("Adds the Spoilers tab to the app")
        }
    }

    private var betSection: some View {
        Section("Season bet text") {
            TextField("Friendly bet", text: $seasonBetText, axis: .vertical)
                .focused($focusedField, equals: .seasonBet)
                .lineLimit(2...4)

            Button("Save bet text") {
                Task {
                    await saveBetText()
                }
            }
            .buttonStyle(.borderedProminent)
            .frame(minHeight: 44)
        }
    }

    private var resetSection: some View {
        Section("Season") {
            Button("Reset season", role: .destructive) {
                showResetConfirmation = true
            }
            .frame(minHeight: 44)
        }
    }

    private var spoilerGateBinding: Binding<Bool> {
        Binding(
            get: { viewModel.settings.spoilerGateEnabled },
            set: { newValue in
                Task {
                    await updateSettings { $0.spoilerGateEnabled = newValue }
                }
            }
        )
    }

    private var spoilersSectionBinding: Binding<Bool> {
        Binding(
            get: { viewModel.settings.showSpoilersSection },
            set: { newValue in
                Task {
                    await updateSettings { $0.showSpoilersSection = newValue }
                }
            }
        )
    }

    private func binding(for playerID: UUID) -> Binding<String> {
        Binding(
            get: { playerNames[playerID, default: ""] },
            set: { playerNames[playerID] = $0 }
        )
    }

    private func hydrateLocalState() {
        // Keep local edits stable while a field is focused, but still reflect external changes.
        let focusedPlayerID: UUID? = {
            if case let .player(id)? = focusedField { return id }
            return nil
        }()

        // Start from existing names and merge in model values for non-focused players.
        var mergedNames = playerNames

        // Remove entries for players that no longer exist.
        let currentIDs = Set(viewModel.players.map { $0.id })
        mergedNames.keys
            .filter { !currentIDs.contains($0) }
            .forEach { mergedNames.removeValue(forKey: $0) }

        // Add/update entries from the model for players not currently being edited.
        for player in viewModel.players {
            guard player.id != focusedPlayerID else {
                // Ensure there's at least a value present while editing.
                if mergedNames[player.id] == nil { mergedNames[player.id] = player.name }
                continue
            }
            mergedNames[player.id] = player.name
        }

        playerNames = mergedNames

        // Only refresh bet text if the user isn't actively editing it.
        if focusedField != .seasonBet {
            seasonBetText = viewModel.settings.seasonBetText
        }
    }

    private func savePlayerNames() async {
        do {
            let updatedPlayers = viewModel.players.map { player in
                Player(id: player.id, name: playerNames[player.id, default: player.name])
            }
            try await viewModel.savePlayers(updatedPlayers)
            viewModel.showInfo("Player names saved")
        } catch {
            viewModel.showError(error.localizedDescription)
        }
    }

    private func addPlayer() async {
        do {
            try await viewModel.addPlayer(named: newPlayerName)
            newPlayerName = ""
            viewModel.showInfo("Player added")
        } catch {
            viewModel.showError(error.localizedDescription)
        }
    }

    private func removePlayer(playerID: UUID) async {
        do {
            try await viewModel.removePlayers(withIDs: [playerID])
            viewModel.showInfo("Player removed")
        } catch {
            viewModel.showError(error.localizedDescription)
        }
    }

    private func saveBetText() async {
        await updateSettings { settings in
            settings.seasonBetText = seasonBetText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        viewModel.showInfo("Season bet saved")
    }

    private func updateSettings(_ mutate: (inout AppSettings) -> Void) async {
        var updated = viewModel.settings
        mutate(&updated)

        do {
            try await viewModel.saveSettings(updated)
        } catch {
            viewModel.showError(error.localizedDescription)
        }
    }

    private func resetSeason() async {
        do {
            try await viewModel.resetSeason()
            viewModel.showInfo("Season reset")
        } catch {
            viewModel.showError(error.localizedDescription)
        }
    }
}
