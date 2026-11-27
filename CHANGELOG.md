# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial repository structure with `project.yml`, generated `Owghat.xcodeproj`, SwiftUI macOS app stub (`Owghat`), WidgetKit extension stub (`OwghatWidget`), and `OwghatTests`.
- `Packages/OwghatCore` Swift 6 package with an offline astronomical prayer-times calculator supporting Tehran (Institute of Geophysics), Jafari, MWL, Umm al-Qura, Egyptian, Karachi, ISNA, and custom calculation parameters.
- Per-prayer minute offsets, date-specific manual time overrides, and next-prayer countdown resolution across midnight and DST transitions.
- Jalali, Hijri (Umm al-Qura and Islamic Civil with ±day moon-sighting offset), and Gregorian calendar conversions plus Persian/Latin numeral formatting.
- Bundled Iranian and world cities (`cities.json`) and religious/official occasions (`occasions.json`) with custom event and JSON import/export support.
- App Group shared `SettingsStore` and `WidgetSnapshot` persistence, `AladhanPrayerTimesProvider` scaffold, and unit tests in `OwghatCoreTests`.
- GitHub Actions CI workflow on `macos-15`, issue templates, `docs/ROADMAP.md`, `CONTRIBUTING.md`, bilingual `README.md`, and MIT `LICENSE`.
