# Owghat (اوقات)

A native macOS prayer-times app written in Swift 6 and SwiftUI, living in your menu bar and Desktop widgets. Everything—from calculation parameters and manual time overrides to calendars, occasions, and Adhan audio—is user-editable.

> **Status:** Early scaffold (`M0` + `M1` complete). `OwghatCore` includes a working offline astronomical engine, calendar converter, bundled city/occasion data, and unit tests; the macOS app and WidgetKit extension are scaffolded for upcoming milestones (see [ROADMAP.md](docs/ROADMAP.md)).

## Screenshots

_Screenshots will be added as the menu bar panel (`M2`) and WidgetKit layouts (`M4`) are finalized._

| Menu Bar Panel | Desktop Widget | Settings |
| :---: | :---: | :---: |
| _Coming in M2_ | _Coming in M4_ | _Coming in M5_ |

## Features

- **Offline-first prayer calculation:** Pure Swift astronomical engine (`OwghatCore`) requiring no internet connection.
- **Multiple calculation methods:** Defaults to **Tehran (Institute of Geophysics, University of Tehran)** (`Fajr 17.7°`, `Maghrib 4.5°`, `Isha 14°`, Shia midnight from sunset to Fajr). Also includes Jafari (Qum), MWL, Umm al-Qura, Egyptian, Karachi, ISNA, and custom angle parameters.
- **Optional online comparison:** Built-in `AladhanPrayerTimesProvider` (`method=7`) with daily caching to compare or override offline times when online.
- **Full time customization:** Per-prayer minute offsets and date-specific manual overrides for Imsak, Fajr, Sunrise, Dhuhr, Sunset, Maghrib, Isha, and Islamic midnight.
- **Menu bar & live countdown:** `MenuBarExtra` (`.window` style) with customizable label (icon only, next prayer + time, countdown, Persian or Latin digits), today's dates, occasions, and quick mute toggle.
- **Desktop & Notification Center widgets:** Small, Medium, and Large WidgetKit families configurable via `AppIntents` and synchronized through a shared App Group.
- **Adhan playback & alerts:** `AVAudioPlayer`-based playback with volume, fade-in, optional pre-Adhan reminder, post-Adhan Doa clip, `UNUserNotificationCenter` backup alerts (Stop/Snooze), wake/timezone re-arming, and `SMAppService` launch at login.
- **Triple calendar & occasions:** Jalali (`.persian`), Hijri (`.islamicUmmAlQura` / `.islamicCivil` with moon-sighting ±day offset), and Gregorian dates, plus bundled Iranian holidays and religious occasions with support for custom events and JSON import/export.
- **Bilingual UI:** Persian (RTL, default) and English via String Catalog (`Localizable.xcstrings`).

## Requirements

- **Runtime:** macOS 14.0 (Sonoma) or later
- **Building the App & Widget:** Xcode 16.0 or later
- **Building/Testing `OwghatCore` only:** Swift 6.0+ toolchain (works with `swift build` / `swift test` without Xcode.app)

## Build & Run

### 1. Run `OwghatCore` Tests (SwiftPM)

```bash
cd Packages/OwghatCore
swift test
```

> **Note on Command Line Tools without Xcode.app:** On macOS machines that only have Command Line Tools installed (without `Xcode.app`), pass the CLT Testing framework paths if `swift test` cannot locate `Testing.framework` automatically:
> ```bash
> swift test -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib
> ```

### 2. Open and Build the macOS App & Widget

The repository commits both `project.yml` and the generated `Owghat.xcodeproj`. You can open `Owghat.xcodeproj` directly in Xcode, or regenerate it after editing `project.yml`:

```bash
brew install xcodegen
xcodegen generate
open Owghat.xcodeproj
```

Before signing or running with App Groups on your own Apple Developer account:
1. Replace the placeholder `com.example` bundle ID prefix in `project.yml`, `Packages/OwghatCore/Sources/OwghatCore/AppConfig.swift`, `Owghat/Resources/Owghat.entitlements`, and `OwghatWidget/Resources/OwghatWidget.entitlements` (or update `OWGHAT_APP_GROUP` in `project.yml`).
2. Set `DEVELOPMENT_TEAM` in `project.yml` and regenerate with `xcodegen generate`.

> **Signed Build Requirement for Widgets:** On macOS, a shared App Group between the app and its WidgetKit extension must be prefixed with your Apple Developer Team ID (`$(TeamIdentifierPrefix)…`, configured once via `OWGHAT_APP_GROUP` in `project.yml`). Unsigned CI or ad-hoc builds compile and run the app, but cannot access the shared App Group container, so widgets fall back to default offline calculations instead of live app settings or snapshot updates.

## Adding Adhan Audio

Owghat does **not** ship any copyrighted Adhan recordings. A minimal royalty-free placeholder chime (`Owghat/Resources/Audio/gentle-chime.wav`) is included for testing alerts.

To use your own Adhan or Doa recordings (`.mp3`, `.m4a`, `.wav`, `.aiff`, `.caf`):
1. Open **Settings → Adhan & Alerts**.
2. Click **Import Audio File…** and select a recording from your Mac (validated to be readable with duration `0 < d ≤ 15 min`).
3. Imported files are copied into `~/Library/Application Support/Owghat/Audio/` and referenced by ID so you can assign different clips per prayer or as a post-Adhan Doa.

> **macOS Sleep Limitation:** When your Mac is asleep at a scheduled prayer time, user-space apps cannot wake the system to play Adhan audio (waking a sleeping Mac requires root-level power scheduling). Upon wake, Owghat skips late audio playback beyond a 90-second grace window and posts a quiet missed-prayer notification if notifications are enabled. If the app was quit, pending system notifications up to 48 hours ahead still alert via macOS Notification Center.

## Calculation Method Notes

| Method | Fajr | Maghrib | Isha | Midnight |
| --- | --- | --- | --- | --- |
| **Tehran (Default)** | 17.7° | 4.5° | 14.0° | Sunset → Next Fajr (Shia) |
| **Jafari (Qum)** | 16.0° | 4.0° | 14.0° | Sunset → Next Fajr (Shia) |
| **MWL** | 18.0° | Sunset (0 min) | 17.0° | Sunset → Next Sunrise |
| **Umm al-Qura** | 18.5° | Sunset (0 min) | 90 min after Maghrib | Sunset → Next Sunrise |
| **Egyptian** | 19.5° | Sunset (0 min) | 17.5° | Sunset → Next Sunrise |
| **Karachi** | 18.0° | Sunset (0 min) | 18.0° | Sunset → Next Sunrise |
| **ISNA** | 15.0° | Sunset (0 min) | 15.0° | Sunset → Next Sunrise |

Sunrise and sunset use a standard `0.833°` solar depression angle (with optional elevation correction). Imsak defaults to 10 minutes before Fajr.

## License

MIT License — see [LICENSE](LICENSE).

---

<div dir="rtl">

# اوقات (Owghat)

اپلیکیشن بومی (Native) نمایش اوقات شرعی برای macOS با Swift 6 و SwiftUI؛ همراه با منوی نوار بالا (Menu Bar)، پخش اذان و ویجت‌های دسکتاپ. تمام بخش‌ها—از روش محاسبه و تغییر دستی ساعات تا تقویم، مناسبت‌ها و فایل‌های صوتی—کاملاً قابل ویرایش توسط کاربر است.

## امکانات اصلی

- **محاسبه آفلاین و بدون نیاز به اینترنت:** موتور نجومی داخلی در پکیج `OwghatCore`.
- **روش‌های محاسبه متنوع:** پیش‌فرض **مؤسسه ژئوفیزیک دانشگاه تهران** (صبح ۱۷٫۷°، مغرب ۴٫۵°، عشا ۱۴°، نیمه‌شب شرعی بین غروب تا اذان صبح) به همراه جعفری، رابطه عالم اسلامی، ام‌القری، مصر، کراچی، ISNA و زوایای دلخواه.
- **امکان مقایسه آنلاین (اختیاری):** دریافت اوقات از Aladhan API (`method=7`) با کش روزانه برای مقایسه با محاسبه آفلاین.
- **ویرایش کامل اوقات:** اعمال اختلاف دقیقه‌ای برای هر وقت و تغییر دستی هر زمان در هر تاریخ دلخواه.
- **نوار منو و شمارش معکوس زنده:** نمایش نام و زمان یا شمارش معکوس با اعداد فارسی یا لاتین، تاریخ‌های هجری شمسی، هجری قمری و میلادی، و مناسبت‌های روز.
- **پخش اذان و هشدارها:** پخش صوتی با کنترل صدا و fade-in، هشدار پیش از اذان، دعای پس از اذان، اعلان سیستم (Stop/Snooze)، پشتیبانی از خواب و بیداری سیستم و تغییر منطقه زمانی، و اجرای خودکار هنگام ورود به سیستم.
- **افزودن فایل صوتی دلخواه:** این پروژه هیچ فایل اذان دارای حق نشر را همراه خود ندارد و فقط یک زنگ آزمایشی رایگان ارائه می‌دهد؛ می‌توانید فایل‌های صوتی دلخواه خود (تا ۱۵ دقیقه) را از بخش تنظیمات وارد کنید تا پس از اعتبارسنجی در پوشه Application Support ذخیره شوند.
- **محدودیت حالت خواب مک (Sleep):** در زمان خواب بودن سیستم، اپلیکیشن‌ها بدون دسترسی ریشه (root) امکان بیدار کردن مک برای پخش صوتی اذان را ندارند؛ پس از بیدار شدن سیستم، اگر بیش از ۹۰ ثانیه از وقت اذان گذشته باشد صوت با تأخیر پخش نمی‌شود و در صورت فعال بودن اعلان‌ها یک اعلان بی‌صدا بابت وقت سپری‌شده نمایش داده می‌شود.

</div>
