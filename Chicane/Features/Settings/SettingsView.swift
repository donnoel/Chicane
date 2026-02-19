import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    @State private var playerNames: [UUID: String] = [:]
    @State private var newPlayerName = ""
    @State private var seasonBetText = ""
    @State private var showResetConfirmation = false
    @State private var statusMessage: String?

    var body: some View {
        Form {
            playerSection
            spoilerSection
            betSection
            resetSection
            aboutSection

            if let statusMessage {
                Section {
                    Text(statusMessage)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.blue)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(LiquidGlassBackground())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
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

    private var aboutSection: some View {
        Section("About & Privacy") {
            Text("No account. Data stored on device.")
            Text("Offline-first MVP with bundled driver/rider lists and calendar placeholders.")
                .foregroundStyle(.secondary)
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
        playerNames = Dictionary(uniqueKeysWithValues: viewModel.players.map { ($0.id, $0.name) })
        seasonBetText = viewModel.settings.seasonBetText
    }

    private func savePlayerNames() async {
        do {
            let updatedPlayers = viewModel.players.map { player in
                Player(id: player.id, name: playerNames[player.id, default: player.name])
            }
            try await viewModel.savePlayers(updatedPlayers)
            statusMessage = "Player names saved"
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private func addPlayer() async {
        do {
            try await viewModel.addPlayer(named: newPlayerName)
            newPlayerName = ""
            statusMessage = "Player added"
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private func removePlayer(playerID: UUID) async {
        do {
            try await viewModel.removePlayers(withIDs: [playerID])
            statusMessage = "Player removed"
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private func saveBetText() async {
        await updateSettings { settings in
            settings.seasonBetText = seasonBetText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        statusMessage = "Season bet saved"
    }

    private func updateSettings(_ mutate: (inout AppSettings) -> Void) async {
        var updated = viewModel.settings
        mutate(&updated)

        do {
            try await viewModel.saveSettings(updated)
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private func resetSeason() async {
        do {
            try await viewModel.resetSeason()
            statusMessage = "Season reset"
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }
}
