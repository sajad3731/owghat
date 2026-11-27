import OwghatCore
import SwiftUI

/// Location, calculation method, and online/offline source settings.
struct PrayerCalculationSettingsView: View {
    let appState: AppState

    var body: some View {
        Form {
            Section("Location") {
                Picker("City", selection: Binding(
                    get: { appState.settings.selectedLocation.id },
                    set: { cityID in
                        if let city = appState.cityDatabase.city(withID: cityID) {
                            appState.updateSettings {
                                $0.locationMode = .cityPreset
                                $0.selectedLocation = city
                            }
                        }
                    }
                )) {
                    ForEach(appState.cityDatabase.cities) { city in
                        Text(city.localizedName(for: appState.settings.language)).tag(city.id)
                    }
                }

                Button("Use Current Mac Location") {
                    appState.locationManager.requestCurrentLocation()
                }
            }

            Section("Calculation") {
                Picker("Method", selection: Binding(
                    get: { appState.settings.calculationMethod.id },
                    set: { methodID in
                        if let matched = CalculationMethod.allPresets.first(where: { $0.id == methodID }) {
                            appState.updateSettings { $0.calculationMethod = matched }
                        }
                    }
                )) {
                    ForEach(CalculationMethod.allPresets) { method in
                        Text(method.localizedName(for: appState.settings.language)).tag(method.id)
                    }
                }

                Picker("Source", selection: Binding(
                    get: { appState.settings.sourceMode },
                    set: { mode in appState.updateSettings { $0.sourceMode = mode } }
                )) {
                    Text("Offline only").tag(PrayerSourceMode.offlineOnly)
                    Text("Online only (Aladhan)").tag(PrayerSourceMode.onlineOnly)
                    Text("Offline + Online diff").tag(PrayerSourceMode.offlineWithOnlineComparison)
                }
            }
        }
        .formStyle(.grouped)
    }
}
