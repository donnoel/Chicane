import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    @State private var playerNames: [UUID: String] = [:]
    @State private var playerBetTextByPlayerID: [UUID: String] = [:]
    @State private var newPlayerName = ""
    @State private var joinLeagueCode = ""
    @State private var showResetConfirmation = false
    @State private var showJoinConfirmation = false
    @State private var showLeaveLeagueConfirmation = false
    @State private var sharedLeagueStatusMessage: String?

    private enum FocusField: Hashable {
        case player(UUID)
        case playerBet(UUID)
        case newPlayer
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
            playerBetSection
            syncSection
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
            Text("This clears all race picks, race results, world champion picks, and season champion results for the season.")
        }
        .alert("Join shared league?", isPresented: $showJoinConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Replace Local Data", role: .destructive) {
                Task {
                    await joinLeague(replacingLocalState: true)
                }
            }
        } message: {
            Text("Joining replaces your current on-device players, picks, results, and champion selections with the shared league state.")
        }
        .alert("Leave shared league?", isPresented: $showLeaveLeagueConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Leave", role: .destructive) {
                Task {
                    await leaveLeague()
                }
            }
        } message: {
            Text("This device will stop syncing with the current shared league. Your local players, picks, and results stay on this device.")
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

    private var playerBetSection: some View {
        Section("Player Bets") {
            if viewModel.players.isEmpty {
                Text("Add players first, then set what each person is betting.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.players) { player in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(player.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField(
                            "What \(player.name) is betting",
                            text: betBinding(for: player.id),
                            axis: .vertical
                        )
                        .focused($focusedField, equals: .playerBet(player.id))
                        .lineLimit(1...3)
                    }
                    .padding(.vertical, 4)
                }

                Button("Save player bets") {
                    Task {
                        await savePlayerBets()
                    }
                }
                .buttonStyle(.borderedProminent)
                .frame(minHeight: 44)
            }
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
                        sharedLeagueStatusMessage = nil
                        await viewModel.syncLeagueIfNeeded(showBannerOnSuccess: true)
                    }
                }
                .buttonStyle(.borderedProminent)
                .frame(minHeight: 44)

                Button("Leave Shared League", role: .destructive) {
                    showLeaveLeagueConfirmation = true
                }
                .frame(minHeight: 44)
            } else {
                if viewModel.isSyncing {
                    ProgressView("Connecting to league…")
                }

                Button("Create Shared League") {
                    Task {
                        sharedLeagueStatusMessage = await viewModel.createLeague()
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

            if let sharedLeagueStatusMessage, !sharedLeagueStatusMessage.isEmpty {
                Text(sharedLeagueStatusMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
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

    private func betBinding(for playerID: UUID) -> Binding<String> {
        Binding(
            get: { playerBetTextByPlayerID[playerID, default: ""] },
            set: { playerBetTextByPlayerID[playerID] = $0 }
        )
    }

    private func hydrateLocalState() {
        // Keep local edits stable while a field is focused, but still reflect external changes.
        let focusedPlayerID: UUID? = {
            if case let .player(id)? = focusedField { return id }
            return nil
        }()
        let focusedBetPlayerID: UUID? = {
            if case let .playerBet(id)? = focusedField { return id }
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

        var mergedBets = playerBetTextByPlayerID
        let storedBets = viewModel.settings.playerBetTextByPlayerID
        mergedBets.keys
            .filter { !currentIDs.contains($0) }
            .forEach { mergedBets.removeValue(forKey: $0) }

        for player in viewModel.players {
            guard player.id != focusedBetPlayerID else {
                if mergedBets[player.id] == nil {
                    mergedBets[player.id] = storedBets[player.id] ?? ""
                }
                continue
            }
            mergedBets[player.id] = storedBets[player.id] ?? ""
        }
        playerBetTextByPlayerID = mergedBets

        if activeLeagueCode != nil {
            joinLeagueCode = ""
            sharedLeagueStatusMessage = nil
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

    private func savePlayerBets() async {
        let validPlayerIDs = Set(viewModel.players.map(\.id))
        let sanitizedBets = playerBetTextByPlayerID.reduce(into: [UUID: String]()) { partialResult, entry in
            guard validPlayerIDs.contains(entry.key) else { return }
            let trimmed = entry.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            partialResult[entry.key] = trimmed
        }

        switch await updateSettings({ settings in
            settings.playerBetTextByPlayerID = sanitizedBets
        }) {
        case .success:
            viewModel.showInfo("Player bets saved")
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

    private var hasLocalSeasonStateToReplace: Bool {
        if !viewModel.players.isEmpty ||
            !viewModel.picks.isEmpty ||
            !viewModel.results.isEmpty ||
            !viewModel.championPicks.isEmpty ||
            !viewModel.championResults.isEmpty {
            return true
        }

        var comparableSettings = viewModel.settings
        comparableSettings.leagueCode = nil
        return comparableSettings != .default
    }

    private func joinLeague(replacingLocalState: Bool = false) async {
        let code = joinLeagueCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        if !replacingLocalState && hasLocalSeasonStateToReplace {
            showJoinConfirmation = true
            return
        }

        sharedLeagueStatusMessage = await viewModel.joinLeague(code: code)
        if activeLeagueCode != nil {
            joinLeagueCode = ""
            sharedLeagueStatusMessage = nil
        }
    }

    private func leaveLeague() async {
        switch await updateSettings({ settings in
            settings.leagueCode = nil
        }) {
        case .success:
            joinLeagueCode = ""
            sharedLeagueStatusMessage = nil
            viewModel.showInfo("Left shared league")
        case let .warning(warning):
            sharedLeagueStatusMessage = warning
            viewModel.showInfo(warning)
        case .failure:
            break
        }
    }
}
