import Foundation
import CoreLocation

/// Manages macOS location tracking with CoreLocation and an 8-second fallback to HTTPS IP Geolocation.
@MainActor
final class LocationManager: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<(String, Double?, Double?), Never>?
    private var hasResolved = false

    override init() {
        super.init()
        manager.delegate = self
        // Optimized for macOS Wi-Fi/Network positioning without GPS hardware
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    }

    func fetchLocation() async -> (String, Double?, Double?) {
        let status = manager.authorizationStatus
        
        // Fall back to IP geolocation if permissions are denied or disabled system-wide
        if status == .denied || status == .restricted || !CLLocationManager.locationServicesEnabled() {
            log(" CoreLocation denied or disabled. Falling back to IP geolocation.")
            return await fetchIPLocation()
        }

        // Prompt for system permission if not yet determined
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }

        manager.startUpdatingLocation()
        log(" CoreLocation scanning started...")

        return await withCheckedContinuation { cont in
            self.continuation = cont
            self.hasResolved = false

            // 8-second timeout task for macOS Wi-Fi positioning
            Task {
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                if !self.hasResolved {
                    log(" CoreLocation timeout (8s). Falling back to IP geolocation.")
                    let ipResult = await self.fetchIPLocation()
                    self.resolveOnce(with: ipResult)
                }
            }
        }
    }

    private func resolveOnce(with result: (String, Double?, Double?)) {
        guard !hasResolved else { return }
        hasResolved = true
        manager.stopUpdatingLocation()
        continuation?.resume(returning: result)
        continuation = nil
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        let desc = "Lat: \(loc.coordinate.latitude), Lon: \(loc.coordinate.longitude)"

        Task { @MainActor in
            log(" CoreLocation fix obtained: \(desc)")
            self.resolveOnce(with: (desc, loc.coordinate.latitude, loc.coordinate.longitude))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            log(" CoreLocation error: \(error.localizedDescription)")
            guard !self.hasResolved else { return }
            let ipResult = await self.fetchIPLocation()
            self.resolveOnce(with: ipResult)
        }
    }

    // MARK: - IP Geolocation Fallback (HTTPS)

    private func fetchIPLocation() async -> (String, Double?, Double?) {
        guard let url = URL(string: "https://ipapi.co/json/") else {
            return ("IP Location Unavailable", nil, nil)
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let lat = json["latitude"] as? Double,
                  let lon = json["longitude"] as? Double,
                  let city = json["city"] as? String,
                  let country = json["country_name"] as? String else {
                return ("IP Location Unavailable", nil, nil)
            }

            let desc = "IP: \(city), \(country) (\(lat), \(lon))"
            log(" IP geolocation obtained: \(desc)")
            return (desc, lat, lon)
        } catch {
            log(" IP geolocation request failed: \(error.localizedDescription)")
            return ("IP Location Unavailable", nil, nil)
        }
    }
}

