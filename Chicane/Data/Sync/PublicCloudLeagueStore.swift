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
        static let loadRecordAttempts = 4
        static let loadRecordRetryDelayNanoseconds: UInt64 = 350_000_000
        static let pushAttempts = 6
        static let pushRetryDelayNanoseconds: UInt64 = 350_000_000
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

        var record = try await loadRecord(for: normalizedCode) ?? CKRecord(
            recordType: Constants.recordType,
            recordID: recordID(for: normalizedCode)
        )
        var lastError: Error?

        for attempt in 1 ... Constants.pushAttempts {
            do {
                var sharedState = state
                sharedState.settings.leagueCode = normalizedCode
                try apply(sharedState, to: record)
                _ = try await database.save(record)
                logger.debug("Synced shared league \(normalizedCode, privacy: .public)")
                return
            } catch let error as CKError where error.code == .serverRecordChanged {
                lastError = error
                logger.error("Push conflict for league \(normalizedCode, privacy: .public) on attempt \(attempt, privacy: .public): \(error.localizedDescription, privacy: .public)")

                let latestServerRecord =
                    error.serverRecord
                    ?? error.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord

                if let latestServerRecord {
                    record = latestServerRecord
                } else {
                    record = try await loadRecord(for: normalizedCode) ?? CKRecord(
                        recordType: Constants.recordType,
                        recordID: recordID(for: normalizedCode)
                    )
                }

                guard attempt < Constants.pushAttempts else {
                    break
                }
            } catch let error as CKError where shouldRetry(error) {
                lastError = error
                logger.error("Transient push failure for league \(normalizedCode, privacy: .public) on attempt \(attempt, privacy: .public): \(error.localizedDescription, privacy: .public)")
                guard attempt < Constants.pushAttempts else {
                    break
                }

                let retryDelay = retryDelayNanoseconds(
                    for: error,
                    fallback: Constants.pushRetryDelayNanoseconds
                )
                try? await Task.sleep(nanoseconds: retryDelay)

                if let latestRecord = try await loadRecord(for: normalizedCode) {
                    record = latestRecord
                }
            } catch {
                throw error
            }
        }

        throw lastError ?? RepositoryError.cloudSyncUnavailable
    }

    private func loadRecord(for code: String) async throws -> CKRecord? {
        var lastError: Error?
        for attempt in 1 ... Constants.loadRecordAttempts {
            do {
                return try await database.record(for: recordID(for: code))
            } catch let error as CKError where error.code == .unknownItem {
                return nil
            } catch let error as CKError where shouldRetry(error) {
                lastError = error
                logger.error("Transient load failure for league \(code, privacy: .public) on attempt \(attempt, privacy: .public): \(error.localizedDescription, privacy: .public)")
                guard attempt < Constants.loadRecordAttempts else {
                    break
                }
                let retryDelay = retryDelayNanoseconds(
                    for: error,
                    fallback: Constants.loadRecordRetryDelayNanoseconds
                )
                try? await Task.sleep(nanoseconds: retryDelay)
            } catch {
                throw error
            }
        }
        throw lastError ?? RepositoryError.cloudSyncUnavailable
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

    private func shouldRetry(_ error: CKError) -> Bool {
        switch error.code {
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return true
        default:
            return false
        }
    }

    private func retryDelayNanoseconds(for error: CKError, fallback: UInt64) -> UInt64 {
        guard let retryAfter = error.retryAfterSeconds, retryAfter > 0 else {
            return fallback
        }
        let nanoseconds = retryAfter * 1_000_000_000
        guard nanoseconds.isFinite, nanoseconds > 0 else {
            return fallback
        }
        return UInt64(nanoseconds.rounded(.up))
    }
}
