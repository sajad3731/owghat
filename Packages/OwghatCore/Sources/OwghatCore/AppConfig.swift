import Foundation

/// Central application identity and identifier configuration.
/// Keep all naming and bundle identifiers here so the app can be renamed in one place.
public enum AppConfig {
    public static let appName = "Owghat"
    public static let persianAppName = "اوقات"

    // TODO: Update bundleIdentifierPrefix to match your reverse-DNS domain and Apple Developer team.
    public static let bundleIdentifierPrefix = "com.example"

    public static let appBundleIdentifier = "\(bundleIdentifierPrefix).owghat"
    public static let widgetBundleIdentifier = "\(bundleIdentifierPrefix).owghat.widget"
    public static let appGroupInfoPlistKey = "OwghatAppGroupIdentifier"
    public static let fallbackAppGroupIdentifier = "group.\(bundleIdentifierPrefix).owghat"
    public static let urlScheme = "owghat"

    public static var appGroupIdentifier: String {
        if let configured = Bundle.main.object(forInfoDictionaryKey: appGroupInfoPlistKey) as? String {
            let trimmed = configured.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, !trimmed.contains("$(") {
                return trimmed
            }
        }
        return fallbackAppGroupIdentifier
    }

    public static let appSupportDirectoryName = "Owghat"
    public static let aladhanBaseURL = URL(string: "https://api.aladhan.com/v1")!
}
