import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @AppStorage(DevicePlayerSelection.storageKey) private var selectedDevicePlayerIDRawValue = ""

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
            devicePlayerSection
            playerSection
            playerBetSection
            syncSection
            resetSection
        }
        .formStyle(.grouped)
        .listSectionSpacing(.compact)
        .tint(.accentColor)
        .scrollContentBackground(.hidden)
        .background(NeutralAppBackground())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.defaultMinListRowHeight, CGFloat(28))
        .environment(\.defaultMinListHeaderHeight, CGFloat(20))
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

    private var devicePlayerSection: some View {
        Section {
            if viewModel.players.isEmpty {
                Text("Add players first.")
                    .font(ChicaneTypography.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 2)
            } else {
                ForEach(viewModel.players) { player in
                    Button {
                        selectedDevicePlayerIDRawValue = DevicePlayerSelection.rawValue(for: player)
                        viewModel.showInfo("This device is set to \(player.name)")
                    } label: {
                        HStack(spacing: 10) {
                            Text(player.name)
                                .font(ChicaneTypography.body)
                                .foregroundStyle(.primary)
                            Spacer()
                            if DevicePlayerSelection.selectedPlayer(
                                in: viewModel.players,
                                rawValue: selectedDevicePlayerIDRawValue
                            )?.id == player.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                                    .accessibilityLabel("Selected")
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Use \(player.name) on this device")
                }
            }
        } header: {
            Text("This Device")
        } footer: {
            Text("Only this player can edit picks on this iPhone or iPad.")
        }
    }

    private var playerSection: some View {
        Section {
            ForEach(viewModel.players) { player in
                HStack(spacing: 8) {
                    TextField("Player name", text: binding(for: player.id))
                        .font(ChicaneTypography.body)
                        .textInputAutocapitalization(.words)
                        .disableAutocorrection(true)
                        .focused($focusedField, equals: .player(player.id))
                        .accessibilityLabel("Name for \(player.name)")
                        .submitLabel(.done)
                        .textFieldStyle(.plain)

                    if viewModel.players.count > 1 {
                        Button(role: .destructive) {
                            Task {
                                await removePlayer(playerID: player.id)
                            }
                        } label: {
                            Image(systemName: "minus.circle")
                                .font(.title3)
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .frame(width: 30, height: 30)
                        .accessibilityLabel("Remove \(player.name)")
                    }
                }
                .frame(minHeight: 28)
            }

            HStack(spacing: 6) {
                Image(systemName: "person.badge.plus")
                    .foregroundStyle(.secondary)

                TextField("Add Player", text: $newPlayerName)
                    .font(ChicaneTypography.body)
                    .textInputAutocapitalization(.words)
                    .disableAutocorrection(true)
                    .focused($focusedField, equals: .newPlayer)
                    .onSubmit {
                        Task { await addPlayer() }
                    }
                    .submitLabel(.done)
                    .textFieldStyle(.plain)

                Button("Add") {
                    Task {
                        await addPlayer()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .labelStyle(.titleOnly)
                .disabled(newPlayerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .frame(minHeight: 28)

            Button("Save Player Names") {
                Task {
                    await savePlayerNames()
                }
            }
            .font(ChicaneTypography.button)
            .disabled(hasBlankPlayerNames)
            .padding(.top, -2)
        } header: {
            Text("Players")
        } footer: {
            Text("Names appear across picks, results, standings, and shared league sync.")
        }
    }

    private var playerBetSection: some View {
        Section {
            if viewModel.players.isEmpty {
                Text("Add players first, then set what each person is betting.")
                    .font(ChicaneTypography.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 2)
            } else {
                ForEach(viewModel.players) { player in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(player.name)
                            .font(ChicaneTypography.captionSemibold)
                            .foregroundStyle(.secondary)
                        TextField(
                            "What \(player.name) is betting",
                            text: betBinding(for: player.id),
                            axis: .vertical
                        )
                        .font(ChicaneTypography.body)
                        .focused($focusedField, equals: .playerBet(player.id))
                        .lineLimit(1...2)
                        .textFieldStyle(.plain)
                        .submitLabel(.done)
                    }
                    .frame(minHeight: 30, alignment: .leading)
                }

                Button("Save Player Bets") {
                    Task {
                        await savePlayerBets()
                    }
                }
                .font(ChicaneTypography.button)
            }
        } header: {
            Text("Player Bets")
        } footer: {
            Text("These notes appear on the Weekend screen under Player bets.")
        }
    }

    private var syncSection: some View {
        Section {
            if let code = activeLeagueCode {
                if viewModel.isSyncing {
                    ProgressView("Syncing league…")
                }

                LabeledContent("League Code") {
                    Text(code)
                        .font(ChicaneTypography.leagueCode)
                        .textSelection(.enabled)
                }

                Text("Use this same code on every phone so picks and results sync through iCloud.")
                    .font(ChicaneTypography.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 1)

                Button("Copy League Code") {
                    if let code = activeLeagueCode {
                        UIPasteboard.general.string = code
                        viewModel.showInfo("League Code Copied")
                    }
                }
                .font(ChicaneTypography.button)
                .padding(.vertical, -1)

                Button("Sync Now") {
                    Task {
                        sharedLeagueStatusMessage = nil
                        await viewModel.syncLeagueIfNeeded(showBannerOnSuccess: true)
                    }
                }
                .font(ChicaneTypography.button)
                .padding(.vertical, -1)

                Button("Leave Shared League", role: .destructive) {
                    showLeaveLeagueConfirmation = true
                }
                .font(ChicaneTypography.button)
                .padding(.vertical, -1)
            } else {
                if viewModel.isSyncing {
                    ProgressView("Connecting to league…")
                }

                Button("Create Shared League") {
                    Task {
                        sharedLeagueStatusMessage = await viewModel.createLeague()
                    }
                }
                .font(ChicaneTypography.button)
                .padding(.vertical, -1)

                Text("Create a shared league on one phone, then enter that code on the other phones.")
                    .font(ChicaneTypography.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 1)

                HStack(spacing: 8) {
                    TextField("Enter League Code", text: $joinLeagueCode)
                        .font(ChicaneTypography.body)
                        .textInputAutocapitalization(.characters)
                        .disableAutocorrection(true)
                        .onSubmit {
                            Task { await joinLeague() }
                        }
                        .textFieldStyle(.plain)
                        .submitLabel(.done)

                    Button("Join") {
                        Task {
                            await joinLeague()
                        }
                    }
                    .font(ChicaneTypography.button)
                    .disabled(joinLeagueCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .frame(minHeight: 28)
            }

            if let sharedLeagueStatusMessage, !sharedLeagueStatusMessage.isEmpty {
                Text(sharedLeagueStatusMessage)
                    .font(ChicaneTypography.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Shared League")
        } footer: {
            Text("Shared leagues sync through iCloud and can replace local season state when joining.")
        }
    }

    private var resetSection: some View {
        Section {
            Button("Reset Season", role: .destructive) {
                showResetConfirmation = true
            }
            .font(ChicaneTypography.button)
        } header: {
            Text("Season")
        } footer: {
            Text("This clears race picks, race results, and champion selections, but keeps players and settings.")
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
            sharedLeagueStatusMessage = warning
            viewModel.showSaveOutcome(warning: warning, successMessage: "Player Names Saved")
        } catch {
            viewModel.showError(error.localizedDescription)
        }
    }

    private func addPlayer() async {
        do {
            let warning = try await viewModel.addPlayer(named: newPlayerName)
            newPlayerName = ""
            sharedLeagueStatusMessage = warning
            viewModel.showSaveOutcome(warning: warning, successMessage: "Player Added")
        } catch {
            viewModel.showError(error.localizedDescription)
        }
    }

    private func removePlayer(playerID: UUID) async {
        do {
            let warning = try await viewModel.removePlayers(withIDs: [playerID])
            sharedLeagueStatusMessage = warning
            viewModel.showSaveOutcome(warning: warning, successMessage: "Player Removed")
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
            sharedLeagueStatusMessage = nil
            viewModel.showInfo("Player bets saved")
        case let .warning(warning):
            sharedLeagueStatusMessage = warning
            viewModel.showError(warning)
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
            sharedLeagueStatusMessage = warning
            viewModel.showSaveOutcome(warning: warning, successMessage: "Season Reset")
        } catch {
            viewModel.showError(error.localizedDescription)
        }
    }

    private var activeLeagueCode: String? {
        viewModel.settings.normalizedLeagueCode
    }

    private var hasBlankPlayerNames: Bool {
        viewModel.players.contains { player in
            playerNames[player.id, default: player.name]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
        }
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
