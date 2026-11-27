import Foundation

/// Converts numbers and time strings between Latin (ASCII) and Persian digits.
public enum DigitFormatter {
    private static let persianDigits: [Character] = ["۰", "۱", "۲", "۳", "۴", "۵", "۶", "۷", "۸", "۹"]

    public static func toPersian(_ input: String) -> String {
        String(input.map { ch in
            if let ascii = ch.asciiValue, ascii >= 48 && ascii <= 57 {
                return persianDigits[Int(ascii - 48)]
            }
            return ch
        })
    }

    public static func toLatin(_ input: String) -> String {
        String(input.map { ch in
            if let idx = persianDigits.firstIndex(of: ch) {
                return Character(UnicodeScalar(48 + idx)!)
            }
            return ch
        })
    }

    public static func format(_ value: String, persianDigits: Bool) -> String {
        persianDigits ? toPersian(value) : value
    }

    public static func formatTime(_ date: Date, timeZone: TimeZone, persianDigits: Bool) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        let raw = formatter.string(from: date)
        return format(raw, persianDigits: persianDigits)
    }
}
