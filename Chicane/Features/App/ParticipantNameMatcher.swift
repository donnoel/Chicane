import Foundation

struct ParticipantNameMatcher {
    func matchingParticipantID(for name: String, participants: [Driver]) -> String? {
        let normalizedTarget = Self.normalizedName(name)
        guard !normalizedTarget.isEmpty else { return nil }

        // Tier 1: exact normalised match.
        if let exact = uniquelyMatchedParticipant(
            in: participants,
            where: { Self.normalizedName($0.name) == normalizedTarget }
        ) {
            return exact.id
        }

        // Tier 2: surname-only match.
        // Split the result name into tokens and consider each token a potential surname,
        // but only if it is long enough to be unambiguous (>= 4 characters).
        let targetTokens = normalizedTarget.split(separator: " ").map(String.init)
        let surnameCandidates = targetTokens.filter { $0.count >= 4 }

        if !surnameCandidates.isEmpty {
            // Find a participant whose normalised name contains at least one of the
            // surname candidates as an exact token — not just a substring.
            if let surnameMatch = uniquelyMatchedParticipant(
                in: participants,
                where: { participant in
                    let participantTokens = Set(Self.normalizedName(participant.name).split(separator: " ").map(String.init))
                    return surnameCandidates.contains(where: { participantTokens.contains($0) })
                }
            ) {
                return surnameMatch.id
            }
        }

        // Tier 3: token-set intersection (at least 2 shared tokens, both sides must be multi-token).
        let targetTokenSet = Set(targetTokens)
        if targetTokenSet.count >= 2 {
            if let tokenMatch = uniquelyMatchedParticipant(
                in: participants,
                where: { participant in
                    let candidateTokens = Set(Self.normalizedName(participant.name).split(separator: " ").map(String.init))
                    guard candidateTokens.count >= 2 else { return false }
                    return candidateTokens.intersection(targetTokenSet).count >= 2
                }
            ) {
                return tokenMatch.id
            }
        }

        return nil
    }

    static func normalizedName(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(
                of: #"[^a-zA-Z0-9 ]"#,
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"\s+"#,
                with: " ",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func uniquelyMatchedParticipant(
        in participants: [Driver],
        where predicate: (Driver) -> Bool
    ) -> Driver? {
        let matches = participants.filter(predicate)
        guard matches.count == 1 else {
            return nil
        }
        return matches[0]
    }
}
