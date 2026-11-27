public enum ManualUpdateCheckResult: Equatable, Sendable {
    case updateAvailable(currentVersion: String, latestVersion: String)
    case upToDate(currentVersion: String)
    case failed(message: String)
}

public enum UpdateReminderPolicy {
    public static func shouldShowCapsule(
        standardDriverWillShowUpdate: Bool,
        updateIsNotDownloaded: Bool
    ) -> Bool {
        !standardDriverWillShowUpdate && updateIsNotDownloaded
    }
}
