import OwghatCore
import SwiftUI

/// Religious occasions, holidays, and custom event management view.
struct EventsSettingsView: View {
    let appState: AppState

    var body: some View {
        List {
            Section("Upcoming Occasions") {
                ForEach(appState.upcomingOccasions) { item in
                    HStack {
                        Text(item.occasion.localizedTitle(for: appState.settings.language))
                        Spacer()
                        Text(item.dateKey)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        }
    }
}
