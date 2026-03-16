import CloudKit
import Foundation

enum CloudSyncErrorFormatter {
    static func describe(_ error: Error) -> String {
        if let ckError = error as? CKError {
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

    private static func describeCloudKitError(_ error: CKError) -> String {
        switch error.code {
        case .permissionFailure:
            return "CloudKit permission failure (`permissionFailure`). Shared league writes are blocked for this account/container. Check iCloud sign-in on this device and CloudKit production permissions/schema for this app."
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
