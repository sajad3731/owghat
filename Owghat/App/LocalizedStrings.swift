import Foundation
import OwghatCore

/// Resolves localized strings from `Localizable.xcstrings` in the active `AppLanguage`.
enum LocalizedStrings {
    static func string(_ key: String, language: AppLanguage) -> String {
        String(
            localized: String.LocalizationValue(key),
            locale: Locale(identifier: language.rawValue)
        )
    }

    static func format(_ key: String, language: AppLanguage, _ args: CVarArg...) -> String {
        let template = string(key, language: language)
        return String(format: template, locale: Locale(identifier: language.rawValue), arguments: args)
    }

    static func systemString(_ key: String) -> String {
        String(localized: String.LocalizationValue(key))
    }
}
