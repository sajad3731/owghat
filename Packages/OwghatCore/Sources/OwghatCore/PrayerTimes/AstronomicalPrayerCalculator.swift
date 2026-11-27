import Foundation

/// Errors raised during prayer time calculation or resolution.
public enum PrayerCalculationError: Error, Sendable, Equatable {
    case invalidDateComponents
    case unableToComputeSolarTimes
}

/// Pure Swift astronomical calculator for Islamic prayer times.
/// Computes physical UTC instants for solar events using USNO/Meeus solar coordinate equations
/// with iterative refinement, handling DST transitions and high-latitude fallbacks.
public struct AstronomicalPrayerCalculator: Sendable {
    private static let unixEpochJulianDate = 2440587.5
    private static let secondsPerDay = 86_400.0
    private static let sunriseDepressionDegrees = 0.833

    public init() {}

    /// Calculates prayer times for a Gregorian date in the specified location and time zone.
    public func calculate(
        for dateComponents: DateComponents,
        location: GeoLocation,
        timeZone: TimeZone,
        method: CalculationMethod = .tehran,
        offsets: [Prayer: Int] = [:],
        manualOverrides: [String: [Prayer: LocalTimeOfDay]] = [:]
    ) throws -> DailyPrayerTimes {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = timeZone

        guard let year = dateComponents.year,
              let month = dateComponents.month,
              let day = dateComponents.day else {
            throw PrayerCalculationError.invalidDateComponents
        }

        let normalizedComponents = DateComponents(year: year, month: month, day: day)
        var noonComponents = normalizedComponents
        noonComponents.hour = 12
        noonComponents.minute = 0
        noonComponents.second = 0

        guard let localNoon = gregorian.date(from: noonComponents),
              let nextDayDate = gregorian.date(byAdding: .day, value: 1, to: localNoon) else {
            throw PrayerCalculationError.invalidDateComponents
        }

        let params = method.parameters
        let rawToday = computeRawTimes(
            localNoon: localNoon,
            location: location,
            params: params
        )

        let rawTomorrow = computeRawTimes(
            localNoon: nextDayDate,
            location: location,
            params: params
        )

        let midnight = computeMidnight(
            sunset: rawToday.sunset,
            nextFajr: rawTomorrow.fajr,
            nextSunrise: rawTomorrow.sunrise,
            mode: params.midnightMode
        )

        let baseTimes: [Prayer: Date] = [
            .imsak: rawToday.fajr.addingTimeInterval(TimeInterval(-params.imsakMinutesBeforeFajr * 60)),
            .fajr: rawToday.fajr,
            .sunrise: rawToday.sunrise,
            .dhuhr: rawToday.dhuhr,
            .sunset: rawToday.sunset,
            .maghrib: rawToday.maghrib,
            .isha: rawToday.isha,
            .midnight: midnight
        ]

        let key = DateKeyFormatter.key(for: normalizedComponents)
        let dayOverrides = manualOverrides[key] ?? [:]

        var entries: [Prayer: PrayerTimeEntry] = [:]
        for prayer in Prayer.allCases {
            guard let baseDate = baseTimes[prayer] else { continue }
            if let overrideTime = dayOverrides[prayer],
               let overrideDate = overrideTime.date(on: normalizedComponents, in: timeZone) {
                entries[prayer] = PrayerTimeEntry(
                    prayer: prayer,
                    date: overrideDate,
                    isOverridden: true,
                    appliedOffsetMinutes: 0
                )
            } else {
                let offsetMinutes = offsets[prayer] ?? 0
                let adjusted = baseDate.addingTimeInterval(TimeInterval(offsetMinutes * 60))
                entries[prayer] = PrayerTimeEntry(
                    prayer: prayer,
                    date: adjusted,
                    isOverridden: false,
                    appliedOffsetMinutes: offsetMinutes
                )
            }
        }

        return DailyPrayerTimes(
            dateKey: key,
            timeZoneIdentifier: timeZone.identifier,
            location: location,
            method: method,
            entries: entries,
            source: .offline
        )
    }

    // MARK: - Raw Astronomical Computation

    private struct RawSolarTimes {
        let fajr: Date
        let sunrise: Date
        let dhuhr: Date
        let sunset: Date
        let maghrib: Date
        let isha: Date
    }

    private func computeRawTimes(
        localNoon: Date,
        location: GeoLocation,
        params: CalculationParameters
    ) -> RawSolarTimes {
        let jdNoon = julianDate(from: localNoon)
        let jdTransit = refineSolarTransit(nearJulianDate: jdNoon, longitude: location.longitude)

        let sunriseDepression = Self.sunriseDepressionDegrees + elevationCorrectionDegrees(location.elevationMeters)
        let sunriseJD = refineSolarDepressionTime(
            jdTransit: jdTransit,
            latitude: location.latitude,
            longitude: location.longitude,
            depressionDegrees: sunriseDepression,
            isMorning: true
        ) ?? (jdTransit - 0.25)

        let sunsetJD = refineSolarDepressionTime(
            jdTransit: jdTransit,
            latitude: location.latitude,
            longitude: location.longitude,
            depressionDegrees: sunriseDepression,
            isMorning: false
        ) ?? (jdTransit + 0.25)

        let sunrise = roundedToNearestMinute(date(fromJulianDate: sunriseJD))
        let dhuhr = roundedToNearestMinute(date(fromJulianDate: jdTransit))
        let sunset = roundedToNearestMinute(date(fromJulianDate: sunsetJD))

        // Estimate night length around this day for high-latitude fallbacks.
        let nightSeconds = max(3600.0, (sunriseJD + 1.0 - sunsetJD) * Self.secondsPerDay)

        let fajrDate: Date
        if let fajrJD = refineSolarDepressionTime(
            jdTransit: jdTransit,
            latitude: location.latitude,
            longitude: location.longitude,
            depressionDegrees: params.fajrAngle,
            isMorning: true
        ) {
            fajrDate = roundedToNearestMinute(date(fromJulianDate: fajrJD))
        } else {
            let portion = nightPortion(rule: params.highLatitudeRule, angle: params.fajrAngle)
            fajrDate = roundedToNearestMinute(sunrise.addingTimeInterval(-nightSeconds * portion))
        }

        let maghribDate: Date
        switch params.maghribRule {
        case .angle(let angle):
            if let maghribJD = refineSolarDepressionTime(
                jdTransit: jdTransit,
                latitude: location.latitude,
                longitude: location.longitude,
                depressionDegrees: angle,
                isMorning: false
            ) {
                maghribDate = roundedToNearestMinute(date(fromJulianDate: maghribJD))
            } else {
                let portion = nightPortion(rule: params.highLatitudeRule, angle: angle)
                maghribDate = roundedToNearestMinute(sunset.addingTimeInterval(nightSeconds * portion))
            }
        case .minutesAfterSunset(let minutes), .minutesAfterMaghrib(let minutes):
            maghribDate = roundedToNearestMinute(sunset.addingTimeInterval(minutes * 60.0))
        }

        let ishaDate: Date
        switch params.ishaRule {
        case .angle(let angle):
            if let ishaJD = refineSolarDepressionTime(
                jdTransit: jdTransit,
                latitude: location.latitude,
                longitude: location.longitude,
                depressionDegrees: angle,
                isMorning: false
            ) {
                ishaDate = roundedToNearestMinute(date(fromJulianDate: ishaJD))
            } else {
                let portion = nightPortion(rule: params.highLatitudeRule, angle: angle)
                ishaDate = roundedToNearestMinute(sunset.addingTimeInterval(nightSeconds * portion))
            }
        case .minutesAfterSunset(let minutes):
            ishaDate = roundedToNearestMinute(sunset.addingTimeInterval(minutes * 60.0))
        case .minutesAfterMaghrib(let minutes):
            ishaDate = roundedToNearestMinute(maghribDate.addingTimeInterval(minutes * 60.0))
        }

        return RawSolarTimes(
            fajr: fajrDate,
            sunrise: sunrise,
            dhuhr: dhuhr,
            sunset: sunset,
            maghrib: maghribDate,
            isha: ishaDate
        )
    }

    private func computeMidnight(
        sunset: Date,
        nextFajr: Date,
        nextSunrise: Date,
        mode: MidnightMode
    ) -> Date {
        let targetEnd: Date = switch mode {
        case .shia: nextFajr
        case .standard: nextSunrise
        }
        let midpoint = sunset.addingTimeInterval(targetEnd.timeIntervalSince(sunset) / 2.0)
        return roundedToNearestMinute(midpoint)
    }

    private func refineSolarTransit(nearJulianDate jdNoon: Double, longitude: Double) -> Double {
        let utcMidnightBase = floor(jdNoon - 0.5) + 0.5
        var candidate = jdNoon

        for _ in 0..<3 {
            let (_, eotHours) = solarPosition(julianDate: candidate)
            let transitUTCHours = 12.0 - eotHours - (longitude / 15.0)
            var nextCandidate = utcMidnightBase + (transitUTCHours / 24.0)
            while nextCandidate - jdNoon > 0.5 { nextCandidate -= 1.0 }
            while nextCandidate - jdNoon < -0.5 { nextCandidate += 1.0 }
            candidate = nextCandidate
        }

        return candidate
    }

    private func refineSolarDepressionTime(
        jdTransit: Double,
        latitude: Double,
        longitude: Double,
        depressionDegrees: Double,
        isMorning: Bool
    ) -> Double? {
        let direction = isMorning ? -1.0 : 1.0
        var candidate = jdTransit + direction * (6.0 / 24.0)

        for _ in 0..<2 {
            let (declinationRad, _) = solarPosition(julianDate: candidate)
            let refinedTransit = refineSolarTransit(nearJulianDate: candidate, longitude: longitude)
            guard let haHours = hourAngleHours(
                depressionDegrees: depressionDegrees,
                latitudeDegrees: latitude,
                declinationRad: declinationRad
            ) else {
                return nil
            }
            candidate = refinedTransit + direction * (haHours / 24.0)
        }

        return candidate
    }

    private func solarPosition(julianDate jd: Double) -> (declinationRad: Double, equationOfTimeHours: Double) {
        let d = jd - 2451545.0
        let gDeg = wrapDegrees(357.529 + 0.98560028 * d)
        let gRad = degreesToRadians(gDeg)
        let qDeg = wrapDegrees(280.459 + 0.98564736 * d)
        let lDeg = wrapDegrees(qDeg + 1.915 * sin(gRad) + 0.020 * sin(2.0 * gRad))
        let lRad = degreesToRadians(lDeg)

        let obliquityRad = degreesToRadians(23.439 - 0.00000036 * d)
        let raRad = atan2(cos(obliquityRad) * sin(lRad), cos(lRad))
        let raHours = wrapHours(radiansToDegrees(raRad) / 15.0)

        var eotHours = (qDeg / 15.0) - raHours
        if eotHours > 12.0 { eotHours -= 24.0 }
        if eotHours < -12.0 { eotHours += 24.0 }

        let declinationRad = asin(sin(obliquityRad) * sin(lRad))
        return (declinationRad, eotHours)
    }

    private func hourAngleHours(
        depressionDegrees: Double,
        latitudeDegrees: Double,
        declinationRad: Double
    ) -> Double? {
        let latRad = degreesToRadians(latitudeDegrees)
        let altitudeRad = degreesToRadians(-depressionDegrees)
        let numerator = sin(altitudeRad) - sin(latRad) * sin(declinationRad)
        let denominator = cos(latRad) * cos(declinationRad)
        guard abs(denominator) > 1e-12 else { return nil }
        let cosHA = numerator / denominator
        guard cosHA >= -1.0 && cosHA <= 1.0 else { return nil }
        return radiansToDegrees(acos(cosHA)) / 15.0
    }

    private func nightPortion(rule: HighLatitudeRule, angle: Double) -> Double {
        switch rule {
        case .none, .middleOfNight:
            return 0.5
        case .oneSeventh:
            return 1.0 / 7.0
        case .angleBased:
            return angle / 60.0
        }
    }

    private func elevationCorrectionDegrees(_ elevationMeters: Double) -> Double {
        guard elevationMeters > 0 else { return 0 }
        return 0.0347 * sqrt(elevationMeters)
    }

    private func roundedToNearestMinute(_ date: Date) -> Date {
        let roundedSeconds = (date.timeIntervalSince1970 / 60.0).rounded() * 60.0
        return Date(timeIntervalSince1970: roundedSeconds)
    }

    private func julianDate(from date: Date) -> Double {
        Self.unixEpochJulianDate + (date.timeIntervalSince1970 / Self.secondsPerDay)
    }

    private func date(fromJulianDate jd: Double) -> Date {
        Date(timeIntervalSince1970: (jd - Self.unixEpochJulianDate) * Self.secondsPerDay)
    }

    private func degreesToRadians(_ deg: Double) -> Double {
        deg * .pi / 180.0
    }

    private func radiansToDegrees(_ rad: Double) -> Double {
        rad * 180.0 / .pi
    }

    private func wrapDegrees(_ deg: Double) -> Double {
        let mod = deg.truncatingRemainder(dividingBy: 360.0)
        return mod >= 0 ? mod : mod + 360.0
    }

    private func wrapHours(_ hours: Double) -> Double {
        let mod = hours.truncatingRemainder(dividingBy: 24.0)
        return mod >= 0 ? mod : mod + 24.0
    }
}
