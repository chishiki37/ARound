import CoreLocation
import Foundation

/// Tracks the phone's GPS position while the audio guide is running and turns it
/// into a short text description that is passed to the AI.
///
/// Created and used on the main thread only.
final class LocationManager: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
  static let shared = LocationManager()

  private let manager = CLLocationManager()
  private let geocoder = CLGeocoder()

  private(set) var lastLocation: CLLocation?
  private(set) var lastPlacemark: CLPlacemark?
  private var lastGeocodedLocation: CLLocation?
  private var isGeocoding = false
  private var wantsUpdates = false

  private override init() {
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyBest
    manager.distanceFilter = 5
    manager.activityType = .fitness
    manager.pausesLocationUpdatesAutomatically = false
  }

  // MARK: - Control

  var isAuthorized: Bool {
    let status = manager.authorizationStatus
    return status == .authorizedWhenInUse || status == .authorizedAlways
  }

  var isDenied: Bool {
    let status = manager.authorizationStatus
    return status == .denied || status == .restricted
  }

  /// Ask for permission (first launch) and warm up a first fix, without tracking continuously.
  func prepare() {
    guard SettingsManager.shared.locationSharingEnabled else { return }
    if manager.authorizationStatus == .notDetermined {
      manager.requestWhenInUseAuthorization()
    } else if isAuthorized, !wantsUpdates {
      manager.requestLocation()
    }
  }

  /// Start continuous updates for the duration of a guide session.
  func start() {
    guard SettingsManager.shared.locationSharingEnabled else { return }
    wantsUpdates = true
    if manager.authorizationStatus == .notDetermined {
      manager.requestWhenInUseAuthorization()
      return
    }
    guard isAuthorized else { return }
    beginUpdates()
  }

  func stop() {
    wantsUpdates = false
    manager.stopUpdatingLocation()
    if backgroundLocationDeclared {
      manager.allowsBackgroundLocationUpdates = false
    }
  }

  private var backgroundLocationDeclared: Bool {
    let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
    return modes.contains("location")
  }

  private func beginUpdates() {
    // Keep updating while the phone is locked in a pocket. Only legal when the
    // "location" background mode is declared in Info.plist.
    if backgroundLocationDeclared {
      manager.allowsBackgroundLocationUpdates = true
      manager.showsBackgroundLocationIndicator = true
    }
    manager.startUpdatingLocation()
  }

  // MARK: - Descriptions

  /// Short label for status pills, e.g. "GPS ±8 m".
  var statusText: String {
    if !SettingsManager.shared.locationSharingEnabled { return "Location off" }
    if isDenied { return "No location access" }
    guard let location = lastLocation else { return "Finding GPS…" }
    let age = Date().timeIntervalSince(location.timestamp)
    if age > 120 { return "GPS stale" }
    return "GPS ±\(Int(location.horizontalAccuracy.rounded())) m"
  }

  /// True when there is a recent, reasonably precise fix.
  var hasGoodFix: Bool {
    guard SettingsManager.shared.locationSharingEnabled, let location = lastLocation else { return false }
    return Date().timeIntervalSince(location.timestamp) <= 120 && location.horizontalAccuracy <= 100
  }

  /// Plain-text description of where the wearer is, written for the AI.
  func contextString() -> String {
    if !SettingsManager.shared.locationSharingEnabled {
      return "Location sharing is turned off, so the wearer's position is unknown."
    }
    if isDenied {
      return "Location is unavailable: the app has not been given location permission."
    }
    guard let location = lastLocation else {
      return "Location is unavailable: there is no GPS fix yet."
    }

    var lines: [String] = []
    let age = Int(Date().timeIntervalSince(location.timestamp).rounded())
    let accuracy = Int(location.horizontalAccuracy.rounded())
    let lat = String(format: "%.5f", location.coordinate.latitude)
    let lon = String(format: "%.5f", location.coordinate.longitude)

    var fix = "GPS position: latitude \(lat), longitude \(lon), accurate to about \(accuracy) m, measured \(max(age, 0)) s ago."
    if age > 120 {
      fix += " This fix is old, so the wearer may have moved."
    }
    if accuracy > 100 {
      fix += " This fix is imprecise, so do not rely on it to pick between nearby places."
    }
    lines.append(fix)

    if let placemark = lastPlacemark {
      var parts: [String] = []
      if let name = placemark.name { parts.append(name) }
      if let street = placemark.thoroughfare, !parts.contains(where: { $0.contains(street) }) {
        parts.append(street)
      }
      for value in [placemark.subLocality, placemark.locality, placemark.administrativeArea, placemark.country] {
        if let value, !parts.contains(value) { parts.append(value) }
      }
      if !parts.isEmpty {
        lines.append("Nearest address: \(parts.joined(separator: ", ")).")
      }
      if let interests = placemark.areasOfInterest, !interests.isEmpty {
        lines.append("Known places at this spot: \(interests.joined(separator: ", ")).")
      }
    }

    if location.speed >= 0.5, location.course >= 0 {
      let speed = String(format: "%.1f", location.speed)
      lines.append("Moving \(LocationManager.compassPoint(for: location.course)) at \(speed) m/s. This is the direction of travel, not necessarily where they are looking.")
    } else if location.speed >= 0 {
      lines.append("The wearer is standing still or moving very slowly.")
    }

    let formatter = DateFormatter()
    formatter.dateFormat = "EEEE d MMMM yyyy, HH:mm"
    lines.append("Local time: \(formatter.string(from: Date())).")

    lines.append("")
    lines.append(contentsOf: NearbyPlacesService.shared.contextLines(
      latitude: location.coordinate.latitude,
      longitude: location.coordinate.longitude,
      course: location.course,
      speed: location.speed
    ))

    return lines.joined(separator: "\n")
  }

  private static func compassPoint(for course: CLLocationDirection) -> String {
    let points = ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
    let index = Int((course / 45.0).rounded()) % 8
    return points[(index + 8) % 8]
  }

  // MARK: - CLLocationManagerDelegate

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    guard isAuthorized else { return }
    if wantsUpdates {
      beginUpdates()
    } else {
      manager.requestLocation()
    }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let location = locations.last, location.horizontalAccuracy >= 0 else { return }
    lastLocation = location
    reverseGeocodeIfNeeded(location)
    NearbyPlacesService.shared.refreshIfNeeded(
      latitude: location.coordinate.latitude,
      longitude: location.coordinate.longitude
    )
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    NSLog("[Location] Update failed: %@", error.localizedDescription)
  }

  private func reverseGeocodeIfNeeded(_ location: CLLocation) {
    guard !isGeocoding else { return }
    if let previous = lastGeocodedLocation, location.distance(from: previous) < 40 { return }
    isGeocoding = true
    geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
      DispatchQueue.main.async {
        guard let self else { return }
        self.isGeocoding = false
        if let placemark = placemarks?.first {
          self.lastPlacemark = placemark
          self.lastGeocodedLocation = location
        } else if let error {
          NSLog("[Location] Reverse geocoding failed: %@", error.localizedDescription)
        }
      }
    }
  }
}
