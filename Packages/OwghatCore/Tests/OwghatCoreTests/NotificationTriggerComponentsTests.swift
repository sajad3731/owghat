import Foundation
import Testing
@testable import OwghatCore

@Suite("Notification trigger components")
struct NotificationTriggerComponentsTests {
    private let tehranTZ = TimeZone(identifier: "Asia/Tehran")!
    private let berlinTZ = TimeZone(identifier: "Europe/Berlin")!

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int = 0, in tz: TimeZone) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: s))!
    }

    /// What `UNCalendarNotificationTrigger` does with the components on a Mac set to `systemTZ`.
    private func resolve(_ components: DateComponents, systemTZ: TimeZone) -> Date? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = systemTZ
        return cal.date(from: components)
    }

    @Test("Tehran prayer on a Mac set to Berlin fires at the same instant")
    func tehranLocationBerlinSystem() {
        // Maghrib 18:35 Tehran (+03:30) is 16:05 Berlin (+01:00) on 2025-03-21.
        let maghrib = date(2025, 3, 21, 18, 35, 27, in: tehranTZ)
        let components = NotificationPlan.triggerComponents(for: maghrib, systemTimeZone: berlinTZ)

        #expect(components.hour == 16)
        #expect(components.minute == 5)
        #expect(components.second == 27)
        #expect(resolve(components, systemTZ: berlinTZ) == maghrib)
    }

    @Test("Components carry Gregorian calendar and the system zone")
    func carriesCalendarAndZone() {
        let fajr = date(2025, 6, 22, 3, 2, in: tehranTZ)
        let components = NotificationPlan.triggerComponents(for: fajr, systemTimeZone: berlinTZ)

        #expect(components.calendar?.identifier == .gregorian)
        #expect(components.timeZone == berlinTZ)
        // Fully specified components resolve to the instant regardless of the reader's default zone.
        #expect(Calendar(identifier: .gregorian).date(from: components) == fajr)
    }

    @Test("Instant is kept across a Berlin DST switch")
    func berlinDSTSwitch() {
        // 2025-03-30 Berlin springs forward 02:00 -> 03:00; 2025-10-26 falls back 03:00 -> 02:00.
        // Instants inside the repeated 02:00-03:00 hour are ambiguous as wall-clock components
        // (see `triggerComponents` docs), so the fall-back case uses an instant outside it.
        for instant in [
            date(2025, 3, 30, 5, 10, in: tehranTZ),   // 03:40 CEST, right after the gap
            date(2025, 10, 26, 12, 0, in: tehranTZ),  // 09:30 CET, after the repeated hour
        ] {
            let components = NotificationPlan.triggerComponents(for: instant, systemTimeZone: berlinTZ)
            #expect(resolve(components, systemTZ: berlinTZ) == instant)
        }
    }

    @Test("Same zone for location and system keeps local wall-clock time")
    func sameZone() {
        let dhuhr = date(2025, 12, 22, 12, 3, in: tehranTZ)
        let components = NotificationPlan.triggerComponents(for: dhuhr, systemTimeZone: tehranTZ)
        #expect(components.year == 2025 && components.month == 12 && components.day == 22)
        #expect(components.hour == 12 && components.minute == 3)
    }
}
