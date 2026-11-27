import CoreLocation
import Foundation
import OwghatCore

/// CoreLocation adapter for automatic location detection on macOS.
@MainActor
final class LocationManager: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var onLocationUpdated: ((GeoLocation) -> Void)?
    var onAuthorizationError: ((String) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func requestCurrentLocation() {
        let status = manager.authorizationStatus
        switch status {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorized, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            onAuthorizationError?("Location permission denied in System Settings.")
        @unknown default:
            manager.requestWhenInUseAuthorization()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            guard let self else { return }
            if status == .authorized || status == .authorizedAlways {
                self.manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        let lat = latest.coordinate.latitude
        let lon = latest.coordinate.longitude
        let alt = max(0, latest.altitude)
        let tzIdentifier = TimeZone.autoupdatingCurrent.identifier

        Task { @MainActor [weak self] in
            let location = GeoLocation(
                id: "core-location",
                name: "Current Location",
                persianName: "موقعیت فعلی",
                countryCode: "",
                latitude: lat,
                longitude: lon,
                timeZoneIdentifier: tzIdentifier,
                elevationMeters: alt
            )
            self?.onLocationUpdated?(location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor [weak self] in
            self?.onAuthorizationError?(message)
        }
    }
}
