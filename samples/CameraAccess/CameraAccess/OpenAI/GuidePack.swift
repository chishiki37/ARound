import Combine
import CoreLocation
import Foundation
import UIKit
import Vision

/// One curated place in a guide pack.
///
/// A place is identified by four things together:
/// - where it is (`latitude`, `longitude`, and `radius`: how far away, in metres, the
///   wearer could plausibly be standing while looking at it),
/// - what it is called (`name` and `aliases`),
/// - what it looks like in words (`visualCues`, which the AI compares with the camera view), and
/// - what it looks like in pictures (reference photos stored on the phone, compared
///   with the camera view by `VisualMatcher`).
struct GuidePackPlace: Codable, Sendable, Identifiable {
  let id: String
  let name: String
  let aliases: [String]
  let latitude: Double
  let longitude: Double
  let radius: Double
  let category: String
  let visualCues: String
  let story: String
  let more: String
  let sources: [String]

  enum CodingKeys: String, CodingKey {
    case id, name, aliases, latitude, longitude, radius, category, visualCues, story, more, sources
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(String.self, forKey: .id)
    name = try values.decode(String.self, forKey: .name)
    latitude = try values.decode(Double.self, forKey: .latitude)
    longitude = try values.decode(Double.self, forKey: .longitude)
    aliases = try values.decodeIfPresent([String].self, forKey: .aliases) ?? []
    radius = try values.decodeIfPresent(Double.self, forKey: .radius) ?? 120
    category = try values.decodeIfPresent(String.self, forKey: .category) ?? "place"
    visualCues = try values.decodeIfPresent(String.self, forKey: .visualCues) ?? ""
    story = try values.decodeIfPresent(String.self, forKey: .story) ?? ""
    more = try values.decodeIfPresent(String.self, forKey: .more) ?? ""
    sources = try values.decodeIfPresent([String].self, forKey: .sources) ?? []
  }
}

/// A set of curated places for one area, with a suggested walking order.
struct GuidePack: Codable, Sendable, Identifiable {
  let id: String
  let name: String
  let city: String
  let version: Int
  let attribution: String
  let route: [String]
  let places: [GuidePackPlace]

  enum CodingKeys: String, CodingKey {
    case id, name, city, version, attribution, route, places
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(String.self, forKey: .id)
    name = try values.decode(String.self, forKey: .name)
    places = try values.decode([GuidePackPlace].self, forKey: .places)
    city = try values.decodeIfPresent(String.self, forKey: .city) ?? ""
    version = try values.decodeIfPresent(Int.self, forKey: .version) ?? 1
    attribution = try values.decodeIfPresent(String.self, forKey: .attribution) ?? ""
    route = try values.decodeIfPresent([String].self, forKey: .route) ?? []
  }

  /// Places in walking order, followed by any that the route does not mention.
  var orderedPlaces: [GuidePackPlace] {
    var ordered: [GuidePackPlace] = []
    for placeID in route {
      if let place = places.first(where: { $0.id == placeID }),
         !ordered.contains(where: { $0.id == placeID }) {
        ordered.append(place)
      }
    }
    for place in places where !ordered.contains(where: { $0.id == place.id }) {
      ordered.append(place)
    }
    return ordered
  }
}

/// A curated place close to the wearer.
struct NearbyPackPlace: Identifiable, Sendable {
  let packID: String
  let packName: String
  let place: GuidePackPlace
  let distance: Double

  var id: String { packID + "/" + place.id }
}

enum PackImportError: LocalizedError {
  case notAPack
  case noPlaces
  case badCoordinates(String)
  case tooLarge

  var errorDescription: String? {
    switch self {
    case .notAPack:
      return "This file is not an ARound guide pack."
    case .noPlaces:
      return "This pack has no places in it."
    case .badCoordinates(let name):
      return "The place \"\(name)\" has coordinates that are not valid."
    case .tooLarge:
      return "This file is too large to be a guide pack."
    }
  }
}

/// Holds the guide packs on this phone: the ones built into the app, the ones the
/// wearer imported, and the reference photos added to each place.
///
/// Used from the main thread only.
final class PackStore: ObservableObject, @unchecked Sendable {
  static let shared = PackStore()

  /// Installed packs, built-in and imported, sorted by name.
  @Published private(set) var packs: [GuidePack] = []
  /// Bumped whenever a reference photo is added or removed, so views refresh.
  @Published private(set) var photoRevision = 0

  /// Feature prints of reference photos, keyed by file path. Filled by `VisualMatcher`.
  var printCache: [String: VNFeaturePrintObservation] = [:]

  private var builtIn: [GuidePack] = []
  private var imported: [GuidePack] = []
  private let fileManager = FileManager.default
  private let hiddenKey = "hiddenBuiltInPacks"

  /// How far from the wearer a curated place is still worth mentioning.
  private let searchRadius: CLLocationDistance = 450
  private let maxPlaces = 6
  /// Only the closest few places include the longer "tell me more" text.
  private let placesWithMore = 3

  private init() {
    reload()
  }

  // MARK: - Storage locations

  private var documents: URL {
    fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
  }

  private var packsFolder: URL {
    documents.appendingPathComponent("Packs", isDirectory: true)
  }

  private var photosFolder: URL {
    documents.appendingPathComponent("PackPhotos", isDirectory: true)
  }

  /// Makes an identifier safe to use as a folder name.
  private static func safe(_ identifier: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    let cleaned = String(identifier.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
    return cleaned.isEmpty ? "_" : cleaned
  }

  private func photoFolder(packID: String, placeID: String) -> URL {
    photosFolder
      .appendingPathComponent(PackStore.safe(packID), isDirectory: true)
      .appendingPathComponent(PackStore.safe(placeID), isDirectory: true)
  }

  // MARK: - Loading

  private var hiddenBuiltInIDs: Set<String> {
    Set(UserDefaults.standard.stringArray(forKey: hiddenKey) ?? [])
  }

  private func reload() {
    // Built into the app: files named pack-*.json.
    var bundled: [GuidePack] = []
    let urls = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
    for url in urls where url.lastPathComponent.hasPrefix("pack-") {
      do {
        bundled.append(try JSONDecoder().decode(GuidePack.self, from: try Data(contentsOf: url)))
      } catch {
        NSLog("[Pack] Could not load built-in %@: %@", url.lastPathComponent, String(describing: error))
      }
    }
    builtIn = bundled

    // Imported by the wearer: Documents/Packs/<id>/pack.json.
    var added: [GuidePack] = []
    let folders = (try? fileManager.contentsOfDirectory(at: packsFolder, includingPropertiesForKeys: nil)) ?? []
    for folder in folders {
      let file = folder.appendingPathComponent("pack.json")
      guard let data = try? Data(contentsOf: file) else { continue }
      if let pack = try? JSONDecoder().decode(GuidePack.self, from: data) {
        added.append(pack)
      }
    }
    imported = added

    // An imported pack replaces a built-in one with the same id.
    let importedIDs = Set(imported.map { $0.id })
    let hidden = hiddenBuiltInIDs
    let visibleBuiltIn = builtIn.filter { !importedIDs.contains($0.id) && !hidden.contains($0.id) }
    packs = (imported + visibleBuiltIn).sorted { $0.name < $1.name }
    NSLog("[Pack] %d guide pack(s) available", packs.count)
  }

  // MARK: - Managing packs

  func isBuiltIn(_ packID: String) -> Bool {
    !imported.contains(where: { $0.id == packID }) && builtIn.contains(where: { $0.id == packID })
  }

  var hasHiddenBuiltIns: Bool {
    let hidden = hiddenBuiltInIDs
    return builtIn.contains(where: { hidden.contains($0.id) })
  }

  func restoreBuiltIns() {
    UserDefaults.standard.removeObject(forKey: hiddenKey)
    reload()
  }

  /// Checks that `data` is a valid pack and installs it. Replaces a pack with the same id.
  @discardableResult
  func importPack(from data: Data) throws -> GuidePack {
    guard data.count <= 5_000_000 else { throw PackImportError.tooLarge }
    let pack: GuidePack
    do {
      pack = try JSONDecoder().decode(GuidePack.self, from: data)
    } catch {
      throw PackImportError.notAPack
    }
    guard !pack.places.isEmpty else { throw PackImportError.noPlaces }
    for place in pack.places {
      let valid = (-90.0...90.0).contains(place.latitude) && (-180.0...180.0).contains(place.longitude)
      guard valid else { throw PackImportError.badCoordinates(place.name) }
    }

    let folder = packsFolder.appendingPathComponent(PackStore.safe(pack.id), isDirectory: true)
    try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
    try data.write(to: folder.appendingPathComponent("pack.json"), options: .atomic)

    // Importing a pack un-hides a built-in one with the same id.
    var hidden = hiddenBuiltInIDs
    hidden.remove(pack.id)
    UserDefaults.standard.set(Array(hidden), forKey: hiddenKey)

    reload()
    return pack
  }

  /// Removes an imported pack and its reference photos. A built-in pack is hidden instead,
  /// and keeps its photos so it can be restored.
  func deletePack(id packID: String) {
    if imported.contains(where: { $0.id == packID }) {
      let folder = packsFolder.appendingPathComponent(PackStore.safe(packID), isDirectory: true)
      try? fileManager.removeItem(at: folder)
      if !builtIn.contains(where: { $0.id == packID }) {
        let photos = photosFolder.appendingPathComponent(PackStore.safe(packID), isDirectory: true)
        try? fileManager.removeItem(at: photos)
      }
    } else {
      var hidden = hiddenBuiltInIDs
      hidden.insert(packID)
      UserDefaults.standard.set(Array(hidden), forKey: hiddenKey)
    }
    reload()
    photoRevision += 1
  }

  // MARK: - Reference photos

  func photoURLs(packID: String, placeID: String) -> [URL] {
    let folder = photoFolder(packID: packID, placeID: placeID)
    let urls = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
    return urls
      .filter { $0.pathExtension.lowercased() == "jpg" }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }
  }

  func photoCount(packID: String, placeID: String) -> Int {
    photoURLs(packID: packID, placeID: placeID).count
  }

  /// Saves a reference photo for a place. Returns false if it could not be saved.
  @discardableResult
  func addPhoto(_ image: UIImage, packID: String, placeID: String) -> Bool {
    let folder = photoFolder(packID: packID, placeID: placeID)
    guard let data = PackStore.downscaled(image, maxDimension: 1024).jpegData(compressionQuality: 0.8) else {
      return false
    }
    do {
      try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
      // Time-based names keep photos in the order they were added.
      let stamp = Int(Date().timeIntervalSince1970 * 1000)
      let name = "\(stamp)-\(String(UUID().uuidString.prefix(6))).jpg"
      try data.write(to: folder.appendingPathComponent(name), options: .atomic)
      photoRevision += 1
      return true
    } catch {
      NSLog("[Pack] Could not save reference photo: %@", error.localizedDescription)
      return false
    }
  }

  func deletePhoto(_ url: URL) {
    try? fileManager.removeItem(at: url)
    printCache.removeValue(forKey: url.path)
    photoRevision += 1
  }

  private static func downscaled(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
    let longest = max(image.size.width, image.size.height)
    guard longest > maxDimension, longest > 0 else { return image }
    let ratio = maxDimension / longest
    let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    return UIGraphicsImageRenderer(size: size, format: format).image { _ in
      image.draw(in: CGRect(origin: .zero, size: size))
    }
  }

  // MARK: - Finding places

  /// Curated places near a position, nearest first.
  func places(nearLatitude latitude: Double, longitude: Double) -> [NearbyPackPlace] {
    let origin = CLLocation(latitude: latitude, longitude: longitude)
    var found: [NearbyPackPlace] = []
    for pack in packs {
      for place in pack.places {
        let distance = origin.distance(from: CLLocation(latitude: place.latitude, longitude: place.longitude))
        if distance <= max(searchRadius, place.radius) {
          found.append(NearbyPackPlace(packID: pack.id, packName: pack.name, place: place, distance: distance))
        }
      }
    }
    found.sort { $0.distance < $1.distance }
    return Array(found.prefix(maxPlaces))
  }

  /// True when a live-lookup place is already covered by a curated one nearby.
  func covers(name: String, latitude: Double, longitude: Double) -> Bool {
    let key = WakeWordListener.normalized(name)
    guard !key.isEmpty else { return false }
    let here = CLLocation(latitude: latitude, longitude: longitude)
    for pack in packs {
      for place in pack.places {
        let there = CLLocation(latitude: place.latitude, longitude: place.longitude)
        guard here.distance(from: there) < 250 else { continue }
        for candidate in [place.name] + place.aliases {
          let other = WakeWordListener.normalized(candidate)
          if !other.isEmpty, key == other || key.contains(other) || other.contains(key) {
            return true
          }
        }
      }
    }
    return false
  }

  /// Lines describing nearby curated places for the AI. Empty when none are close.
  func contextLines(latitude: Double, longitude: Double, course: Double, speed: Double) -> [String] {
    let nearby = places(nearLatitude: latitude, longitude: longitude)
    guard let first = nearby.first else { return [] }

    var lines = ["Curated guide pack \"\(first.packName)\" — places near the wearer, nearest first:"]
    for (index, entry) in nearby.enumerated() {
      let place = entry.place
      let position = NearbyPlacesService.positionText(
        fromLatitude: latitude, fromLongitude: longitude,
        toLatitude: place.latitude, toLongitude: place.longitude,
        distance: entry.distance, course: course, speed: speed
      )
      var line = "- \(place.name) (\(place.category)): \(position)."
      if entry.distance <= place.radius {
        line += " The wearer is close enough to be looking at it."
      }
      if !place.visualCues.isEmpty {
        line += " Looks like: \(place.visualCues)"
      }
      if !place.story.isEmpty {
        line += " Story: \(place.story)"
      }
      if index < placesWithMore, !place.more.isEmpty {
        line += " If they ask for more: \(place.more)"
      }
      lines.append(line)
    }
    return lines
  }
}
