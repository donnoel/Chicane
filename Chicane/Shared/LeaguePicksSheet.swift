import SwiftUI

struct LeaguePicksSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedDetent = PresentationDetent.large

    let event: RaceEvent
    let players: [Player]
    let currentPlayerID: UUID?
    let picks: [RacePick]
    let championPicks: [SeasonChampionPick]
    let drivers: [Driver]
    var showsChampionPicks = false

    private var tint: Color {
        ChicaneTheme.seriesColor(event.series)
    }

    private var participantSingular: String {
        event.series == .motoGP ? "rider" : "driver"
    }

    private var compactDetent: PresentationDetent {
        .height(560)
    }

    private var initialDetent: PresentationDetent {
        horizontalSizeClass == .regular ? .large : compactDetent
    }

    private var presentationDetents: Set<PresentationDetent> {
        horizontalSizeClass == .regular ? [.medium, .large] : [compactDetent, .large]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header

                    ForEach(players) { player in
                        playerCard(for: player)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
            }
            .navigationTitle("League picks")
            .navigationBarTitleDisplayMode(.inline)
            .chicaneBackground()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents(presentationDetents, selection: $selectedDetent)
        .presentationDragIndicator(.visible)
        .onAppear {
            selectedDetent = initialDetent
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(event.title)
                .font(ChicaneTypography.cardTitleStrong)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(event.series.shortTitle) podium picks")
                .font(ChicaneTypography.subtitle)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func playerCard(for player: Player) -> some View {
        let pick = podiumPick(for: player)
        let championPick = championPick(for: player)
        let isCurrentPlayer = player.id == currentPlayerID

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Text(initials(from: player.name))
                    .font(ChicaneTypography.initials)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(tint, in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(player.name)
                        .font(ChicaneTypography.bodySemibold)
                    if isCurrentPlayer {
                        Text("This device")
                            .font(ChicaneTypography.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                statusBadge(title: pick == nil ? "Open" : "Ready", tint: pick == nil ? .secondary : tint)
            }

            if let pick {
                podiumRows(for: pick.podium)
            } else {
                emptyRow("No saved podium pick yet.", systemImage: "clock")
            }

            if showsChampionPicks {
                Divider().opacity(0.28)
                if let championPick {
                    championRow(driverID: championPick.driverID)
                } else {
                    emptyRow("No champion pick yet.", systemImage: "person.crop.square")
                }
            }
        }
        .groupedCard(accent: isCurrentPlayer ? tint : .secondary)
        .accessibilityElement(children: .contain)
    }

    private func podiumRows(for podium: Podium) -> some View {
        VStack(spacing: 8) {
            podiumRow(position: 1, driverID: podium.p1)
            podiumRow(position: 2, driverID: podium.p2)
            podiumRow(position: 3, driverID: podium.p3)
        }
    }

    private func podiumRow(position: Int, driverID: String) -> some View {
        HStack(spacing: 10) {
            PodiumMedalView(position: position, isSelected: true)
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)

            Text(participantDisplayLabel(for: driverID))
                .font(ChicaneTypography.body)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Position \(position), \(participantDisplayLabel(for: driverID))")
    }

    private func championRow(driverID: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "trophy.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(ChicaneTheme.glowAmber)
                .frame(width: 32, height: 32)
                .background(ChicaneTheme.glowAmber.opacity(0.14), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("World champion")
                    .font(ChicaneTypography.captionSemibold)
                    .foregroundStyle(.secondary)
                Text(participantDisplayLabel(for: driverID))
                    .font(ChicaneTypography.body)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func emptyRow(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(ChicaneTypography.body)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statusBadge(title: String, tint: Color) -> some View {
        Text(title)
            .font(ChicaneTypography.badgeStrong)
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.14), in: Capsule())
    }

    private func podiumPick(for player: Player) -> RacePick? {
        picks.first {
            $0.series == event.series &&
            $0.eventID == event.id &&
            $0.playerID == player.id
        }
    }

    private func championPick(for player: Player) -> SeasonChampionPick? {
        championPicks.first {
            $0.series == event.series &&
            $0.playerID == player.id
        }
    }

    private func participantDisplayLabel(for participantID: String) -> String {
        if let driver = drivers.first(where: { $0.id == participantID }) {
            return "\(driver.name) (\(driver.team))"
        }
        return fallbackParticipantLabel(from: participantID)
    }

    private func fallbackParticipantLabel(from participantID: String) -> String {
        let trimmed = participantID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "Unknown \(participantSingular)"
        }

        let tokens = trimmed
            .replacingOccurrences(of: #"[_-]+"#, with: " ", options: .regularExpression)
            .split(separator: " ")
            .map(String.init)

        let filtered = tokens.enumerated().compactMap { index, token -> String? in
            let lowered = token.lowercased()
            if index == 0 && (lowered == "f1" || lowered == "mgp" || lowered == "motogp" || lowered == "formula1") {
                return nil
            }
            return token
        }

        guard !filtered.isEmpty else {
            return trimmed
        }
        return filtered.map { $0.capitalized }.joined(separator: " ")
    }

    private func initials(from name: String) -> String {
        let words = name.split(separator: " ")
        let letters = words.prefix(2).compactMap { $0.first }.map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }
}
