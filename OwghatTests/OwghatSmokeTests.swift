import Foundation
import Testing
@testable import OwghatCore

@Suite("Owghat App Smoke Tests")
struct OwghatSmokeTests {
    @Test("Default configuration exposes Owghat identity and Tehran method")
    func defaultConfigSmokeTest() throws {
        #expect(AppConfig.appName == "Owghat")
        #expect(AppSettings.default.calculationMethod == .tehran)

        let calc = AstronomicalPrayerCalculator()
        let schedule = try calc.calculate(
            for: DateComponents(year: 2025, month: 3, day: 21),
            location: .tehran,
            timeZone: TimeZone(identifier: "Asia/Tehran")!
        )
        #expect(schedule.time(for: .fajr) != nil)
    }
}
