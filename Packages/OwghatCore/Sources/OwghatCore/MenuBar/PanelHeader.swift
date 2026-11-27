import Foundation

/// Pure, localized header metadata for the menu bar panel and main overview.
public struct PanelHeader: Sendable, Equatable {
    public let locationName: String
    public let methodName: String
    public let jalaliLine: String
    public let hijriDateText: String
    public let gregorianDateText: String
    public let secondaryDateLine: String

    public init(
        locationName: String,
        methodName: String,
        jalaliLine: String,
        hijriDateText: String,
        gregorianDateText: String,
        secondaryDateLine: String
    ) {
        self.locationName = locationName
        self.methodName = methodName
        self.jalaliLine = jalaliLine
        self.hijriDateText = hijriDateText
        self.gregorianDateText = gregorianDateText
        self.secondaryDateLine = secondaryDateLine
    }

    /// Builds localized header lines with language-appropriate punctuation and digit script.
    public static func build(
        location: GeoLocation,
        method: CalculationMethod,
        dates: TripleCalendarDate,
        language: AppLanguage,
        usePersianDigits: Bool
    ) -> PanelHeader {
        let jalaliDate = dates.jalali.formattedLong(persianDigits: usePersianDigits)
        let jalaliSeparator = language == .persian ? "، " : ", "
        let jalaliLine = "\(dates.jalali.weekdayName)\(jalaliSeparator)\(jalaliDate)"

        let hijriText = dates.hijri.formattedLong(persianDigits: usePersianDigits)
        let gregorianText = dates.gregorian.formattedLong(persianDigits: usePersianDigits)
        let secondarySeparator = " · "
        let secondaryDateLine = "\(hijriText)\(secondarySeparator)\(gregorianText)"

        return PanelHeader(
            locationName: location.localizedName(for: language),
            methodName: method.localizedName(for: language),
            jalaliLine: jalaliLine,
            hijriDateText: hijriText,
            gregorianDateText: gregorianText,
            secondaryDateLine: secondaryDateLine
        )
    }
}
