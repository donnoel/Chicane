import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    @State private var playerNames: [UUID: String] = [:]
    @State private var newPlayerName = ""
    @State private var seasonBetText = ""
    @State private var joinLeagueCode = ""
    @State private var showResetConfirmation = false

    private enum FocusField: Hashable {
        case player(UUID)
        case newPlayer
        case seasonBet
    }

    private enum SettingsSaveOutcome {
        case success
        case warning(String)
        case failure
    }

    @FocusState private var focusedField: FocusField?

    var body: some View {
        Form {
            playerSection
            syncSection
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

            Button("Save Player Names") {
                Task {
                    await savePlayerNames()
                }
            }
            .buttonStyle(.borderedProminent)
            .frame(minHeight: 44)

            HStack(spacing: 10) {
                TextField("Add Player", text: $newPlayerName)
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
                .disabled(newPlayerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var betSection: some View {
        Section("Season Bet Text") {
            TextField("Friendly Bet", text: $seasonBetText, axis: .vertical)
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

    private var syncSection: some View {
        Section("Shared League") {
            if let code = activeLeagueCode {
                if viewModel.isSyncing {
                    ProgressView("Syncing league…")
                }

                LabeledContent("League Code") {
                    Text(code)
                        .font(.headline.monospaced())
                        .textSelection(.enabled)
                }

                Text("Use this same code on every phone so picks and results sync through iCloud.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button("Copy League Code") {
                    UIPasteboard.general.string = code
                    viewModel.showInfo("League Code Copied")
                }
                .frame(minHeight: 44)

                Button("Sync Now") {
                    Task {
                        await viewModel.syncLeagueIfNeeded(showBannerOnSuccess: true)
                    }
                }
                .buttonStyle(.borderedProminent)
                .frame(minHeight: 44)
            } else {
                if viewModel.isSyncing {
                    ProgressView("Connecting to league…")
                }

                Button("Create Shared League") {
                    Task {
                        await viewModel.createLeague()
                    }
                }
                .buttonStyle(.borderedProminent)
                .frame(minHeight: 44)

                Text("Create a shared league on one phone, then enter that code on the other phones.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    TextField("Enter League Code", text: $joinLeagueCode)
                        .textInputAutocapitalization(.characters)
                        .disableAutocorrection(true)
                        .onSubmit {
                            Task { await joinLeague() }
                        }

                    Button("Join") {
                        Task {
                            await joinLeague()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(minHeight: 44)
                    .disabled(joinLeagueCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var resetSection: some View {
        Section("Season") {
            Button("Reset Season", role: .destructive) {
                showResetConfirmation = true
            }
            .frame(minHeight: 44)
        }
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

        if activeLeagueCode != nil {
            joinLeagueCode = ""
        }
    }

    private func savePlayerNames() async {
        do {
            let updatedPlayers = viewModel.players.map { player in
                Player(id: player.id, name: playerNames[player.id, default: player.name])
            }
            let warning = try await viewModel.savePlayers(updatedPlayers)
            viewModel.showInfo(warning ?? "Player Names Saved")
        } catch {
            viewModel.showError(error.localizedDescription)
        }
    }

    private func addPlayer() async {
        do {
            let warning = try await viewModel.addPlayer(named: newPlayerName)
            newPlayerName = ""
            viewModel.showInfo(warning ?? "Player Added")
        } catch {
            viewModel.showError(error.localizedDescription)
        }
    }

    private func removePlayer(playerID: UUID) async {
        do {
            let warning = try await viewModel.removePlayers(withIDs: [playerID])
            viewModel.showInfo(warning ?? "Player Removed")
        } catch {
            viewModel.showError(error.localizedDescription)
        }
    }

    private func saveBetText() async {
        switch await updateSettings({ settings in
            settings.seasonBetText = seasonBetText.trimmingCharacters(in: .whitespacesAndNewlines)
        }) {
        case .success:
            viewModel.showInfo("Season bet saved")
        case let .warning(warning):
            viewModel.showInfo(warning)
        case .failure:
            break
        }
    }

    private func updateSettings(_ mutate: (inout AppSettings) -> Void) async -> SettingsSaveOutcome {
        var updated = viewModel.settings
        mutate(&updated)

        do {
            if let warning = try await viewModel.saveSettings(updated) {
                return .warning(warning)
            }
            return .success
        } catch {
            viewModel.showError(error.localizedDescription)
            return .failure
        }
    }

    private func resetSeason() async {
        do {
            let warning = try await viewModel.resetSeason()
            viewModel.showInfo(warning ?? "Season Reset")
        } catch {
            viewModel.showError(error.localizedDescription)
        }
    }

    private var activeLeagueCode: String? {
        let trimmed = viewModel.settings.leagueCode?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard let trimmed, !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func joinLeague() async {
        let code = joinLeagueCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        await viewModel.joinLeague(code: code)
        if activeLeagueCode != nil {
            joinLeagueCode = ""
        }
    }
}
