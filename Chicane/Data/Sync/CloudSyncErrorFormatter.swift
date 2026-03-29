import CloudKit
import Foundation

enum CloudSyncErrorFormatter {
    static func describe(_ error: Error) -> String {
        if let warning = error as? DeferredCloudSyncWarning {
            return describe(warning.underlyingError)
        }

        if let repositoryError = error as? RepositoryError {
            switch repositoryError {
            case .cloudSyncPermissionDenied:
                return permissionDeniedDescription
            default:
                break
            }
        }

        let cloudKitErrors = collectCloudKitErrors(from: error)
        if let permissionError = cloudKitErrors.first(where: isPermissionFailure) {
            return describeCloudKitError(permissionError)
        }
        if let ckError = cloudKitErrors.first {
            return describeCloudKitError(ckError)
        }

        let nsError = error as NSError
        let detail = nsError.localizedDescription
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if detail.isEmpty {
            return "\(nsError.domain) (\(nsError.code))"
        }
        return "\(detail) [\(nsError.domain):\(nsError.code)]"
    }

    static func containsPermissionFailure(_ error: Error) -> Bool {
        if let repositoryError = error as? RepositoryError,
           case .cloudSyncPermissionDenied = repositoryError {
            return true
        }
        return collectCloudKitErrors(from: error).contains(where: isPermissionFailure)
    }

    private static func describeCloudKitError(_ error: CKError) -> String {
        switch error.code {
        case .permissionFailure:
            return permissionDeniedDescription
        case .notAuthenticated:
            return "Not signed in to iCloud (`notAuthenticated`)."
        case .networkUnavailable, .networkFailure:
            return "Network unavailable (`\(error.code.readableName)`)."
        case .serviceUnavailable, .requestRateLimited, .zoneBusy:
            if let retryAfter = error.retryAfterSeconds, retryAfter > 0 {
                let seconds = Int(retryAfter.rounded(.up))
                return "CloudKit is temporarily busy (`\(error.code.readableName)`), retry in about \(seconds)s."
            }
            return "CloudKit is temporarily busy (`\(error.code.readableName)`)."
        case .serverRecordChanged:
            return "Another player updated the league at the same time (`serverRecordChanged`). Retrying should merge both saves."
        default:
            let detail = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            if detail.isEmpty {
                return "CloudKit error (`\(error.code.readableName)`)."
            }
            return "\(detail) (`\(error.code.readableName)`)"
        }
    }

    private static var permissionDeniedDescription: String {
        "CloudKit permission failure (`permissionFailure`). Shared league writes are blocked for this account/container. Check iCloud sign-in on this device and CloudKit production permissions/schema for this app."
    }

    private static func isPermissionFailure(_ error: CKError) -> Bool {
        error.code == .permissionFailure
    }

    private static func collectCloudKitErrors(from error: Error) -> [CKError] {
        var collected: [CKError] = []
        var queue: [NSError] = [error as NSError]
        var visited = Set<ObjectIdentifier>()

        while let current = queue.popLast() {
            let identifier = ObjectIdentifier(current)
            if visited.contains(identifier) {
                continue
            }
            visited.insert(identifier)

            if let cloudError = current as Error as? CKError {
                collected.append(cloudError)
            }

            for nested in nestedErrors(from: current) {
                queue.append(nested)
            }
        }

        return collected
    }

    private static func nestedErrors(from error: NSError) -> [NSError] {
        var nested: [NSError] = []

        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            nested.append(underlying)
        } else if let underlyingError = error.userInfo[NSUnderlyingErrorKey] as? Error {
            nested.append(underlyingError as NSError)
        }

        if let partialByItem = error.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: NSError] {
            nested.append(contentsOf: partialByItem.values)
        } else if let partialByItem = error.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error] {
            nested.append(contentsOf: partialByItem.values.map { $0 as NSError })
        }

        for value in error.userInfo.values {
            if let nestedError = value as? NSError {
                nested.append(nestedError)
            } else if let nestedError = value as? Error {
                nested.append(nestedError as NSError)
            } else if let nestedArray = value as? [NSError] {
                nested.append(contentsOf: nestedArray)
            } else if let nestedArray = value as? [Error] {
                nested.append(contentsOf: nestedArray.map { $0 as NSError })
            } else if let nestedDictionary = value as? [AnyHashable: NSError] {
                nested.append(contentsOf: nestedDictionary.values)
            } else if let nestedDictionary = value as? [AnyHashable: Error] {
                nested.append(contentsOf: nestedDictionary.values.map { $0 as NSError })
            }
        }

        return nested
    }
}

private extension CKError.Code {
    var readableName: String {
        switch self {
        case .permissionFailure:
            return "permissionFailure"
        case .notAuthenticated:
            return "notAuthenticated"
        case .networkUnavailable:
            return "networkUnavailable"
        case .networkFailure:
            return "networkFailure"
        case .serviceUnavailable:
            return "serviceUnavailable"
        case .requestRateLimited:
            return "requestRateLimited"
        case .zoneBusy:
            return "zoneBusy"
        case .serverRecordChanged:
            return "serverRecordChanged"
        default:
            return "code\(rawValue)"
        }
    }
}
