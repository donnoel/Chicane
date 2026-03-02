import CloudKit
import Foundation
import OSLog

actor PublicCloudLeagueStore: LeagueSyncStore {
    static let containerIdentifier = "iCloud.dn.chicane"

    private enum Constants {
        static let recordType = "LeagueState"
        static let stateDataField = "stateData"
        static let updatedAtField = "updatedAt"
        static let codeLength = 6
        static let createAttempts = 8
    }

    private let database: CKDatabase
    private let logger = Logger(subsystem: "dn.chicane", category: "PublicCloudLeagueStore")

    init(container: CKContainer = CKContainer(identifier: PublicCloudLeagueStore.containerIdentifier)) {
        self.database = container.publicCloudDatabase
    }

    func createLeague(from state: PersistedState) async throws -> PersistedState {
        for _ in 0 ..< Constants.createAttempts {
            let code = makeLeagueCode()
            guard try await loadRecord(for: code) == nil else {
                continue
            }

            var sharedState = state
            sharedState.settings.leagueCode = code
            sharedState.updatedAt = Date()

            let record = CKRecord(recordType: Constants.recordType, recordID: recordID(for: code))
            try apply(sharedState, to: record)
            _ = try await database.save(record)
            return sharedState
        }

        throw RepositoryError.cloudSyncUnavailable
    }

    func joinLeague(code: String) async throws -> PersistedState {
        let normalizedCode = normalized(code)
        guard let state = try await fetchState(for: normalizedCode) else {
            throw RepositoryError.leagueNotFound(code: normalizedCode)
        }
        return state
    }

    func fetchState(for code: String) async throws -> PersistedState? {
        let normalizedCode = normalized(code)
        guard !normalizedCode.isEmpty else {
            return nil
        }

        guard let record = try await loadRecord(for: normalizedCode) else {
            return nil
        }

        let state = try decodeState(from: record, leagueCode: normalizedCode)
        return state
    }

    func pushState(_ state: PersistedState, for code: String) async throws {
        let normalizedCode = normalized(code)
        guard !normalizedCode.isEmpty else {
            throw RepositoryError.leagueNotConfigured
        }

        let record = try await loadRecord(for: normalizedCode) ?? CKRecord(
            recordType: Constants.recordType,
            recordID: recordID(for: normalizedCode)
        )

        var sharedState = state
        sharedState.settings.leagueCode = normalizedCode
        try apply(sharedState, to: record)
        _ = try await database.save(record)
        logger.debug("Synced shared league \(normalizedCode, privacy: .public)")
    }

    private func loadRecord(for code: String) async throws -> CKRecord? {
        do {
            return try await database.record(for: recordID(for: code))
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    private func apply(_ state: PersistedState, to record: CKRecord) throws {
        record[Constants.stateDataField] = try encodedState(state) as NSData
        record[Constants.updatedAtField] = state.updatedAt as NSDate
    }

    private func decodeState(from record: CKRecord, leagueCode: String) throws -> PersistedState {
        guard let data = record[Constants.stateDataField] as? Data else {
            throw RepositoryError.cloudSyncUnavailable
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var state = try decoder.decode(PersistedState.self, from: data).normalized()
        state.settings.leagueCode = leagueCode
        return state
    }

    private func encodedState(_ state: PersistedState) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(state)
    }

    private func recordID(for code: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "league-\(code)")
    }

    private func normalized(_ code: String) -> String {
        let allowed = code.uppercased().filter { $0.isLetter || $0.isNumber }
        return String(allowed.prefix(Constants.codeLength))
    }

    private func makeLeagueCode() -> String {
        let source = UUID().uuidString.replacingOccurrences(of: "-", with: "").uppercased()
        return String(source.prefix(Constants.codeLength))
    }
}
