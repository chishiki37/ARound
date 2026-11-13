import CoreLocation
import Foundation
import MapKit

/// One named place close to the wearer.
struct NearbyPlace: Sendable {
  let name: String
  let latitude: Double
  let longitude: Double
  var category: String?
  var summary: String?
}

/// Looks up what is around the wearer so the guide can match what the camera sees
/// to a real, named place instead of guessing from memory.
///
/// Two sources, both queried with the phone's coordinates:
/// - Apple Maps points of interest (names and categories, within ~250 m)
/// - Wikipedia articles about nearby places (names and a short summary, within ~500 m)
///
/// Results are cached and refreshed after the wearer moves about 60 m.
final class NearbyPlacesService: @unchecked Sendable {
  static let shared = NearbyPlacesService()

  private let lock = NSLock()
  private var places: [NearbyPlace] = []
  private var fetchedAt: Date?
  private var fetchedLatitude: Double = 0
  private var fetchedLongitude: Double = 0
  private var isFetching = false

  private let mapsRadius: CLLocationDistance = 250
  private let wikipediaRadius = 500
  private let refreshDistance: CLLocationDistance = 60
  private let maxAge: TimeInterval = 600
  private let maxPlaces = 14

  private init() {}

  // MARK: - Refreshing

  /// Starts a background refresh if the wearer has moved or the list is old.
  func refreshIfNeeded(latitude: Double, longitude: Double) {
    guard needsRefresh(latitude: latitude, longitude: longitude) else { return }
    Task {
      await self.refresh(latitude: latitude, longitude: longitude)
    }
  }

  /// Refreshes if needed and waits (up to `timeout` seconds) for the list to be ready.
  func refreshAndWait(latitude: Double, longitude: Double, timeout: TimeInterval) async {
    refreshIfNeeded(latitude: latitude, longitude: longitude)
    let deadline = Date().addingTimeInterval(timeout)
    while fetchInProgress(), Date() < deadline {
      try? await Task.sleep(nanoseconds: 100_000_000)
    }
  }

  private func refresh(latitude: Double, longitude: Double) async {
    guard beginFetch() else { return }
    async let mapPlaces = fetchAppleMaps(latitude: latitude, longitude: longitude)
    async let wikiPlaces = fetchWikipedia(latitude: latitude, longitude: longitude)
    let merged = merge(wiki: await wikiPlaces, maps: await mapPlaces, latitude: latitude, longitude: longitude)
    store(merged, latitude: latitude, longitude: longitude)
    NSLog("[Nearby] %d places found near the wearer", merged.count)
  }

  private func needsRefresh(latitude: Double, longitude: Double) -> Bool {
    guard SettingsManager.shared.locationSharingEnabled else { return false }
    return lock.withLock {
      if isFetching { return false }
      guard let fetchedAt else { return true }
      if Date().timeIntervalSince(fetchedAt) > maxAge { return true }
      let previous = CLLocation(latitude: fetchedLatitude, longitude: fetchedLongitude)
      let current = CLLocation(latitude: latitude, longitude: longitude)
      return current.distance(from: previous) > refreshDistance
    }
  }

  private func fetchInProgress() -> Bool {
    lock.withLock { isFetching }
  }

  private func beginFetch() -> Bool {
    lock.withLock {
      if isFetching { return false }
      isFetching = true
      return true
    }
  }

  private func store(_ newPlaces: [NearbyPlace], latitude: Double, longitude: Double) {
    lock.withLock {
      places = newPlaces
      fetchedAt = Date()
      fetchedLatitude = latitude
      fetchedLongitude = longitude
      isFetching = false
    }
  }

  private func snapshot() -> [NearbyPlace] {
    lock.withLock { places }
  }

  // MARK: - Sources

  @MainActor
  private func fetchAppleMaps(latitude: Double, longitude: Double) async -> [NearbyPlace] {
    let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    let request = MKLocalPointsOfInterestRequest(center: center, radius: mapsRadius)
    let search = MKLocalSearch(request: request)
    do {
      let response = try await search.start()
      var results: [NearbyPlace] = []
      for item in response.mapItems {
        guard let name = item.name, !name.isEmpty else { continue }
        let coordinate = item.placemark.coordinate
        results.append(
          NearbyPlace(
            name: name,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            category: NearbyPlacesService.readableCategory(item.pointOfInterestCategory?.rawValue),
            summary: nil
          )
        )
      }
      return results
    } catch {
      NSLog("[Nearby] Apple Maps lookup failed: %@", error.localizedDescription)
      return []
    }
  }

  private func fetchWikipedia(latitude: Double, longitude: Double) async -> [NearbyPlace] {
    var components = URLComponents(string: "https://en.wikipedia.org/w/api.php")
    components?.queryItems = [
      URLQueryItem(name: "action", value: "query"),
      URLQueryItem(name: "format", value: "json"),
      URLQueryItem(name: "formatversion", value: "2"),
      URLQueryItem(name: "generator", value: "geosearch"),
      URLQueryItem(name: "ggscoord", value: "\(latitude)|\(longitude)"),
      URLQueryItem(name: "ggsradius", value: "\(wikipediaRadius)"),
      URLQueryItem(name: "ggslimit", value: "12"),
      URLQueryItem(name: "prop", value: "coordinates|extracts|description"),
      URLQueryItem(name: "colimit", value: "max"),
      URLQueryItem(name: "exintro", value: "1"),
      URLQueryItem(name: "explaintext", value: "1"),
      URLQueryItem(name: "exsentences", value: "2"),
      URLQueryItem(name: "exlimit", value: "max")
    ]
    guard let url = components?.url else { return [] }

    var request = URLRequest(url: url)
    request.timeoutInterval = 6
    request.setValue("ARound/1.0 (personal audio guide app)", forHTTPHeaderField: "User-Agent")

    do {
      let (data, _) = try await URLSession.shared.data(for: request)
      guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let query = json["query"] as? [String: Any],
            let pages = query["pages"] as? [[String: Any]] else {
        return []
      }
      var results: [NearbyPlace] = []
      for page in pages {
        guard let title = page["title"] as? String,
              let coordinates = page["coordinates"] as? [[String: Any]],
              let first = coordinates.first,
              let lat = (first["lat"] as? NSNumber)?.doubleValue,
              let lon = (first["lon"] as? NSNumber)?.doubleValue else {
          continue
        }
        let extract = (page["extract"] as? String)?
          .replacingOccurrences(of: "\n", with: " ")
          .trimmingCharacters(in: .whitespacesAndNewlines)
        results.append(
          NearbyPlace(
            name: title,
            latitude: lat,
            longitude: lon,
            category: page["description"] as? String,
            summary: NearbyPlacesService.shortened(extract, limit: 260)
          )
        )
      }
      return results
    } catch {
      NSLog("[Nearby] Wikipedia lookup failed: %@", error.localizedDescription)
      return []
    }
  }

  // MARK: - Merging

  /// Wikipedia entries carry the stories; Apple Maps fills in everything else nearby.
  private func merge(wiki: [NearbyPlace], maps: [NearbyPlace], latitude: Double, longitude: Double) -> [NearbyPlace] {
    var merged = wiki
    for place in maps {
      let key = NearbyPlacesService.normalized(place.name)
      let here = CLLocation(latitude: place.latitude, longitude: place.longitude)
      let duplicateIndex = merged.firstIndex { existing in
        let otherKey = NearbyPlacesService.normalized(existing.name)
        guard !key.isEmpty, !otherKey.isEmpty else { return false }
        let sameName = key == otherKey || key.contains(otherKey) || otherKey.contains(key)
        let there = CLLocation(latitude: existing.latitude, longitude: existing.longitude)
        return sameName && here.distance(from: there) < 200
      }
      if let duplicateIndex {
        if merged[duplicateIndex].category == nil {
          merged[duplicateIndex].category = place.category
        }
      } else {
        merged.append(place)
      }
    }

    let origin = CLLocation(latitude: latitude, longitude: longitude)
    let sorted = merged.sorted { first, second in
      origin.distance(from: CLLocation(latitude: first.latitude, longitude: first.longitude))
        < origin.distance(from: CLLocation(latitude: second.latitude, longitude: second.longitude))
    }
    return Array(sorted.prefix(maxPlaces))
  }

  // MARK: - Description for the AI

  /// Lines describing the cached places relative to where the wearer is now.
  /// `course` is the direction of travel in degrees, or negative when unknown.
  func contextLines(latitude: Double, longitude: Double, course: Double, speed: Double) -> [String] {
    // Curated pack places come first; they work offline and carry checked stories.
    let packLines = PackStore.shared.contextLines(
      latitude: latitude, longitude: longitude, course: course, speed: speed
    )

    let origin = CLLocation(latitude: latitude, longitude: longitude)
    var liveLines: [String] = []

    for place in snapshot() {
      let target = CLLocation(latitude: place.latitude, longitude: place.longitude)
      let distance = origin.distance(from: target)
      guard distance <= 650 else { continue }
      // Skip anything the curated pack already describes.
      if PackStore.shared.covers(name: place.name, latitude: place.latitude, longitude: place.longitude) {
        continue
      }

      let position = NearbyPlacesService.positionText(
        fromLatitude: latitude, fromLongitude: longitude,
        toLatitude: place.latitude, toLongitude: place.longitude,
        distance: distance, course: course, speed: speed
      )

      var line = "- \(place.name)"
      if let category = place.category, !category.isEmpty {
        line += " (\(category))"
      }
      line += ": \(position)."
      if let summary = place.summary, !summary.isEmpty {
        line += " Wikipedia: \(summary)"
      }
      liveLines.append(line)
    }

    var lines = packLines
    if !liveLines.isEmpty {
      if !lines.isEmpty { lines.append("") }
      lines.append(packLines.isEmpty
        ? "Nearby places, nearest first (from Apple Maps and Wikipedia):"
        : "Other nearby places, nearest first (from Apple Maps and Wikipedia):")
      lines.append(contentsOf: liveLines)
    }
    if lines.isEmpty {
      return ["Nearby places: none found yet for this spot."]
    }
    return lines
  }

  /// "about 40 m to the north-east, ahead on their path"
  static func positionText(
    fromLatitude: Double, fromLongitude: Double,
    toLatitude: Double, toLongitude: Double,
    distance: Double, course: Double, speed: Double
  ) -> String {
    if distance < 15 {
      return "right here"
    }
    let bearing = NearbyPlacesService.bearing(
      fromLatitude: fromLatitude, fromLongitude: fromLongitude,
      toLatitude: toLatitude, toLongitude: toLongitude
    )
    let rounded = max(10, Int((distance / 10).rounded()) * 10)
    var position = "about \(rounded) m to the \(NearbyPlacesService.compassPoint(for: bearing))"
    if speed >= 0.5 && course >= 0 {
      position += ", \(NearbyPlacesService.relativeDirection(bearing: bearing, course: course))"
    }
    return position
  }

  // MARK: - Helpers

  private static func normalized(_ name: String) -> String {
    String(name.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
  }

  private static func shortened(_ text: String?, limit: Int) -> String? {
    guard let text, !text.isEmpty else { return nil }
    if text.count <= limit { return text }
    return String(text.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
  }

  /// "MKPOICategoryNationalPark" -> "national park"
  private static func readableCategory(_ rawValue: String?) -> String? {
    guard var value = rawValue, !value.isEmpty else { return nil }
    if value.hasPrefix("MKPOICategory") {
      value = String(value.dropFirst("MKPOICategory".count))
    }
    var words = ""
    for character in value {
      if character.isUppercase, !words.isEmpty {
        words.append(" ")
      }
      words.append(character)
    }
    return words.lowercased()
  }

  private static func bearing(fromLatitude: Double, fromLongitude: Double, toLatitude: Double, toLongitude: Double) -> Double {
    let lat1 = fromLatitude * .pi / 180
    let lat2 = toLatitude * .pi / 180
    let deltaLon = (toLongitude - fromLongitude) * .pi / 180
    let y = sin(deltaLon) * cos(lat2)
    let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
    let degrees = atan2(y, x) * 180 / .pi
    return (degrees + 360).truncatingRemainder(dividingBy: 360)
  }

  private static func compassPoint(for bearing: Double) -> String {
    let points = ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
    let index = Int((bearing / 45.0).rounded()) % 8
    return points[(index + 8) % 8]
  }

  /// Where a place lies relative to the direction the wearer is walking.
  private static func relativeDirection(bearing: Double, course: Double) -> String {
    let difference = (bearing - course + 360).truncatingRemainder(dividingBy: 360)
    switch difference {
    case 0..<45, 315...360: return "ahead on their path"
    case 45..<135: return "to the right of their path"
    case 135..<225: return "behind them"
    default: return "to the left of their path"
    }
  }
}
