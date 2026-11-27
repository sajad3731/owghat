import OwghatCore
import SwiftUI

/// Popover panel shown when clicking the Owghat menu bar item.
struct MenuBarPanelView: View {
    let appState: AppState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerSection
            Divider()
            nextPrayerBanner
            prayerTimesList
            if !appState.todayOccasions.isEmpty {
                Divider()
                occasionsSection
            }
            Divider()
            footerActions
        }
        .padding(14)
        .frame(width: 340)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(appState.settings.selectedLocation.localizedName(for: appState.settings.language))
                    .font(.headline)
                Spacer()
                Text(appState.settings.calculationMethod.localizedName(for: appState.settings.language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let dates = appState.dates {
                let persianDigits = appState.settings.usePersianDigits
                Text("\(dates.jalali.weekdayName)، \(dates.jalali.formattedLong(persianDigits: persianDigits))")
                    .font(.subheadline)
                HStack(spacing: 8) {
                    Text(dates.hijri.formattedLong(persianDigits: persianDigits))
                    Text("•")
                    Text(dates.gregorian.formattedLong(persianDigits: persianDigits))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var nextPrayerBanner: some View {
        if let next = appState.nextPrayer {
            HStack {
                Label(
                    next.entry.prayer.localizedName(for: appState.settings.language),
                    systemImage: next.entry.prayer.symbolName
                )
                .font(.headline)
                Spacer()
                Text(
                    next.formattedCountdown(
                        persianDigits: appState.settings.usePersianDigits,
                        includeSeconds: true,
                        includeMinusPrefix: false
                    )
                )
                .font(.system(.title3, design: .rounded).monospacedDigit().weight(.semibold))
            }
            .padding(10)
            .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    @ViewBuilder
    private var prayerTimesList: some View {
        if let schedule = appState.todaySchedule {
            let entries = schedule.orderedEntries(filteredBy: appState.settings.visiblePrayers)
            VStack(spacing: 6) {
                ForEach(entries) { entry in
                    let isNext = appState.nextPrayer?.entry.prayer == entry.prayer
                    HStack {
                        Image(systemName: entry.prayer.symbolName)
                            .frame(width: 18)
                            .foregroundStyle(isNext ? Color.accentColor : Color.secondary)
                        Text(entry.prayer.localizedName(for: appState.settings.language))
                            .fontWeight(isNext ? .semibold : .regular)
                        Spacer()
                        if entry.isOverridden {
                            Image(systemName: "pencil")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(
                            DigitFormatter.formatTime(
                                entry.date,
                                timeZone: appState.activeTimeZone,
                                persianDigits: appState.settings.usePersianDigits
                            )
                        )
                        .monospacedDigit()
                        .fontWeight(isNext ? .semibold : .regular)
                    }
                    .padding(.vertical, 3)
                    .padding(.horizontal, 6)
                    .background(isNext ? Color.accentColor.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }

    private var occasionsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey("menubar.occasions"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(appState.todayOccasions) { occasion in
                HStack(spacing: 6) {
                    Circle()
                        .fill(occasion.isOfficialHoliday ? Color.red : Color.accentColor)
                        .frame(width: 6, height: 6)
                    Text(occasion.localizedTitle(for: appState.settings.language))
                        .font(.caption)
                }
            }
        }
    }

    private var footerActions: some View {
        HStack {
            Button {
                appState.toggleMuteToday()
            } label: {
                Label(
                    LocalizedStringKey("menubar.mute_today"),
                    systemImage: appState.isMutedToday ? "bell.slash.fill" : "bell"
                )
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            if appState.isPlayingAdhan {
                Button(LocalizedStringKey("menubar.stop_adhan")) {
                    appState.stopAdhanPlayback()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            Spacer()

            Button(LocalizedStringKey("menubar.open_settings")) {
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            }
            .controlSize(.small)

            Button(LocalizedStringKey("menubar.quit")) {
                NSApplication.shared.terminate(nil)
            }
            .controlSize(.small)
        }
    }
}
