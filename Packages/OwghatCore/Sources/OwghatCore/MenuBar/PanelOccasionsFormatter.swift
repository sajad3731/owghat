import Foundation

/// Display-ready occasion section for the menu bar panel (today's occasions or nearest upcoming).
public struct PanelOccasionsDisplay: Sendable, Equatable {
    public struct Item: Sendable, Equatable, Identifiable {
        public let id: String
        public let title: String
        public let isOfficialHoliday: Bool
        public let relativeDateText: String?

        public init(
            id: String,
            title: String,
            isOfficialHoliday: Bool,
            relativeDateText: String? = nil
        ) {
            self.id = id
            self.title = title
            self.isOfficialHoliday = isOfficialHoliday
            self.relativeDateText = relativeDateText
        }
    }

    public let isShowingUpcoming: Bool
    public let items: [Item]

    public init(isShowingUpcoming: Bool, items: [Item]) {
        self.isShowingUpcoming = isShowingUpcoming
        self.items = items
    }

    /// Formats today's occasions if present; otherwise picks the nearest upcoming occasion within `upcomingOccasions`.
    public static func build(
        todayOccasions: [Occasion],
        upcomingOccasions: [DatedOccasion],
        now: Date,
        timeZone: TimeZone,
        language: AppLanguage,
        usePersianDigits: Bool
    ) -> PanelOccasionsDisplay? {
        if !todayOccasions.isEmpty {
            let items = todayOccasions.map { occasion in
                Item(
                    id: occasion.id,
                    title: occasion.localizedTitle(for: language),
                    isOfficialHoliday: occasion.isOfficialHoliday,
                    relativeDateText: nil
                )
            }
            return PanelOccasionsDisplay(isShowingUpcoming: false, items: items)
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let todayStart = calendar.startOfDay(for: now)

        let future = upcomingOccasions
            .compactMap { dated -> (dated: DatedOccasion, daysUntil: Int)? in
                let targetStart = calendar.startOfDay(for: dated.date)
                let days = calendar.dateComponents([.day], from: todayStart, to: targetStart).day ?? 0
                guard days > 0 else { return nil }
                return (dated, days)
            }
            .min { $0.daysUntil < $1.daysUntil }

        guard let nearest = future else {
            return nil
        }

        let relativeText: String
        if nearest.daysUntil == 1 {
            relativeText = language == .persian ? "فردا" : "Tomorrow"
        } else {
            let daysString = DigitFormatter.format(String(nearest.daysUntil), persianDigits: usePersianDigits)
            relativeText = language == .persian ? "\(daysString) روز دیگر" : "in \(daysString) days"
        }

        let item = Item(
            id: nearest.dated.id,
            title: nearest.dated.occasion.localizedTitle(for: language),
            isOfficialHoliday: nearest.dated.occasion.isOfficialHoliday,
            relativeDateText: relativeText
        )
        return PanelOccasionsDisplay(isShowingUpcoming: true, items: [item])
    }
}
