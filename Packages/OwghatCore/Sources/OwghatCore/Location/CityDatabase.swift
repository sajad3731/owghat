import Foundation

/// Provides bundled Iranian and major world cities loaded from `cities.json`.
public struct CityDatabase: Sendable {
    public let cities: [GeoLocation]

    public init(cities: [GeoLocation]? = nil) {
        if let cities {
            self.cities = cities
        } else {
            self.cities = Self.loadBundledCities()
        }
    }

    public func search(_ query: String) -> [GeoLocation] {
        let trimmed = normalizeArabicPersian(query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        guard !trimmed.isEmpty else { return cities }
        return cities.filter { city in
            let en = city.name.lowercased()
            let fa = normalizeArabicPersian(city.persianName.lowercased())
            let country = city.countryCode.lowercased()
            return en.contains(trimmed) || fa.contains(trimmed) || country == trimmed
        }
    }

    public func city(withID id: String) -> GeoLocation? {
        cities.first { $0.id == id }
    }

    private func normalizeArabicPersian(_ text: String) -> String {
        text
            .replacingOccurrences(of: "ي", with: "ی")
            .replacingOccurrences(of: "ك", with: "ک")
    }

    private static func loadBundledCities() -> [GeoLocation] {
        guard let url = Bundle.module.url(forResource: "cities", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([GeoLocation].self, from: data),
              !decoded.isEmpty else {
            return [.tehran]
        }
        return decoded
    }
}
