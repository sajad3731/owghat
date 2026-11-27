import AppKit
import OwghatCore
import SwiftUI

/// Popover and main overview panel displaying dates, next prayer ring, prayer rows, occasions, and quick actions.
struct MenuBarPanelView: View {
    let appState: AppState
    var showsOpenWindowButton: Bool = true

    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            let schedule = buildPanelSchedule(at: now)
            let header = buildPanelHeader()
            let occasions = buildOccasionsDisplay(at: now)

            VStack(alignment: .leading, spacing: 12) {
                headerSection(header: header)
                Divider()
                nextPrayerCard(schedule: schedule)
                prayerTimesList(schedule: schedule)

                if let occasions {
                    Divider()
                    occasionsSection(display: occasions)
                }

                if let status = appState.statusMessage, !status.isEmpty {
                    statusWarningRow(message: status)
                }

                Divider()
                footerActions
            }
            .padding(14)
            .frame(minWidth: 340, maxWidth: showsOpenWindowButton ? 340 : 440)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
    }

    // MARK: - Core View-Model Builders

    private func buildPanelHeader() -> PanelHeader? {
        guard let dates = appState.dates else { return nil }
        return PanelHeader.build(
            location: appState.settings.selectedLocation,
            method: appState.settings.calculationMethod,
            dates: dates,
            language: appState.settings.language,
            usePersianDigits: appState.settings.usePersianDigits
        )
    }

    private func buildPanelSchedule(at now: Date) -> PanelSchedule {
        PanelSchedule.build(
            todaySchedule: appState.todaySchedule,
            tomorrowSchedule: appState.tomorrowSchedule,
            yesterdaySchedule: appState.yesterdaySchedule,
            visiblePrayers: appState.settings.visiblePrayers,
            now: now,
            timeZone: appState.activeTimeZone,
            language: appState.settings.language,
            usePersianDigits: appState.settings.usePersianDigits
        )
    }

    private func buildOccasionsDisplay(at now: Date) -> PanelOccasionsDisplay? {
        PanelOccasionsDisplay.build(
            todayOccasions: appState.todayOccasions,
            upcomingOccasions: appState.upcomingOccasions,
            now: now,
            timeZone: appState.activeTimeZone,
            language: appState.settings.language,
            usePersianDigits: appState.settings.usePersianDigits
        )
    }

    // MARK: - Sections

    @ViewBuilder
    private func headerSection(header: PanelHeader?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Button {
                    appState.selectedSettingsTab = .calculation
                    WindowFocusHelper.openSettings(using: openSettings)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                            .font(.caption)
                            .foregroundStyle(appState.accentColor)
                        Text(header?.locationName ?? appState.settings.selectedLocation.localizedName(for: appState.settings.language))
                            .font(.headline)
                    }
                }
                .buttonStyle(.plain)
                .help(LocalizedStringKey("menubar.location_settings_hint"))
                .accessibilityLabel(LocalizedStringKey("menubar.location_settings_hint"))

                Spacer(minLength: 8)

                Text(header?.methodName ?? appState.settings.calculationMethod.localizedName(for: appState.settings.language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            if let header {
                Text(header.jalaliLine)
                    .font(.subheadline.weight(.medium))
                Text(header.secondaryDateLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func nextPrayerCard(schedule: PanelSchedule) -> some View {
        if let nextRow = schedule.nextRow {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(.quaternary, lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: schedule.progress)
                        .stroke(appState.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: nextRow.prayer.symbolName)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(appState.accentColor)
                }
                .frame(width: 42, height: 42)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(schedule.nextBannerTitle ?? nextRow.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(nextRow.formattedTime)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Spacer(minLength: 8)

                Text(schedule.liveCountdownText)
                    .font(.system(.title3, design: .rounded).monospacedDigit().weight(.semibold))
            }
            .padding(10)
            .background(appState.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(nextRow.accessibilityLabel)
        }
    }

    @ViewBuilder
    private func prayerTimesList(schedule: PanelSchedule) -> some View {
        if schedule.rows.isEmpty {
            Text(LocalizedStringKey("menubar.no_prayers"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 6)
        } else {
            VStack(spacing: 4) {
                ForEach(Array(schedule.rows.enumerated()), id: \.element.id) { index, row in
                    if row.isTomorrow && (index == 0 || !schedule.rows[index - 1].isTomorrow) {
                        HStack(spacing: 6) {
                            Text(LocalizedStringKey("menubar.tomorrow"))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            VStack { Divider() }
                        }
                        .padding(.top, 4)
                    }

                    prayerRowView(row: row)
                }
            }
        }
    }

    private func prayerRowView(row: PanelPrayerRow) -> some View {
        HStack(spacing: 8) {
            Image(systemName: row.prayer.symbolName)
                .frame(width: 18)
                .foregroundStyle(symbolColor(for: row.state))

            Text(row.title)
                .font(.body)
                .fontWeight(row.state == .next ? .semibold : .regular)
                .foregroundStyle(textColor(for: row.state))

            Spacer(minLength: 8)

            if row.isOverridden {
                Image(systemName: "pencil")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .help(LocalizedStringKey("menubar.manual_override"))
            }

            Text(row.formattedTime)
                .font(.body.monospacedDigit())
                .fontWeight(row.state == .next ? .semibold : .regular)
                .foregroundStyle(textColor(for: row.state))
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            row.state == .next ? appState.accentColor.opacity(0.12) : Color.clear,
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .opacity(row.state == .passed ? 0.58 : 1.0)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.accessibilityLabel)
        .accessibilityAddTraits(row.state == .next ? .isSelected : [])
    }

    private func symbolColor(for state: PrayerRowState) -> Color {
        switch state {
        case .next: return appState.accentColor
        case .passed, .upcoming: return .secondary
        }
    }

    private func textColor(for state: PrayerRowState) -> Color {
        switch state {
        case .passed: return .secondary
        case .next, .upcoming: return .primary
        }
    }

    private func occasionsSection(display: PanelOccasionsDisplay) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(LocalizedStringKey(display.isShowingUpcoming ? "menubar.upcoming_occasion" : "menubar.occasions"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(display.items) { item in
                HStack(spacing: 6) {
                    Circle()
                        .fill(item.isOfficialHoliday ? Color.red : appState.accentColor)
                        .frame(width: 6, height: 6)
                    Text(item.title)
                        .font(.caption)
                    if let relative = item.relativeDateText {
                        Spacer(minLength: 6)
                        Text(relative)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func statusWarningRow(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(2)
            Spacer(minLength: 4)
            Button {
                appState.dismissStatusMessage()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(LocalizedStringKey("menubar.dismiss_warning"))
            .help(LocalizedStringKey("menubar.dismiss_warning"))
        }
        .padding(8)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var footerActions: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Button {
                    appState.toggleMuteToday()
                } label: {
                    Label(
                        LocalizedStringKey(appState.isMutedToday ? "menubar.muted_today" : "menubar.mute_today"),
                        systemImage: appState.isMutedToday ? "bell.slash.fill" : "bell"
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .keyboardShortcut("m", modifiers: .command)
                .accessibilityLabel(LocalizedStringKey(appState.isMutedToday ? "menubar.muted_today" : "menubar.mute_today"))

                if appState.isPlayingAdhan {
                    Button {
                        appState.stopAdhanPlayback()
                    } label: {
                        Label(LocalizedStringKey("menubar.stop_adhan"), systemImage: "stop.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .accessibilityLabel(LocalizedStringKey("menubar.stop_adhan"))
                }

                Spacer(minLength: 4)

                Button {
                    Task { await appState.refreshSchedule(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(appState.isRefreshing)
                .keyboardShortcut("r", modifiers: .command)
                .help(LocalizedStringKey("menubar.refresh"))
                .accessibilityLabel(LocalizedStringKey("menubar.refresh"))
            }

            HStack(spacing: 6) {
                if showsOpenWindowButton {
                    Button {
                        WindowFocusHelper.openMainWindow(using: openWindow)
                    } label: {
                        Label(LocalizedStringKey("menubar.open_window"), systemImage: "macwindow")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .accessibilityLabel(LocalizedStringKey("menubar.open_window"))
                }

                Spacer(minLength: 4)

                Button {
                    WindowFocusHelper.openSettings(using: openSettings)
                } label: {
                    Text(LocalizedStringKey("menubar.open_settings"))
                }
                .controlSize(.small)
                .keyboardShortcut(",", modifiers: .command)
                .accessibilityLabel(LocalizedStringKey("menubar.open_settings"))

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Text(LocalizedStringKey("menubar.quit"))
                }
                .controlSize(.small)
                .keyboardShortcut("q", modifiers: .command)
                .accessibilityLabel(LocalizedStringKey("menubar.quit"))
            }
        }
    }
}
