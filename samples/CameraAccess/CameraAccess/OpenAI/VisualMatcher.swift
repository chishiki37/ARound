import Foundation
import UIKit
import Vision

/// Compares what the camera sees with the reference photos of nearby pack places.
///
/// Each photo is turned into a "feature print" (a numeric fingerprint of the image)
/// by Apple's Vision framework, entirely on the phone. Two prints can be compared:
/// the smaller the distance, the more alike the two pictures look overall.
///
/// This measures overall resemblance, not "the same building", so the result is
/// passed to the guide as supporting evidence next to location and the written description.
enum VisualMatcher {
  // Distance thresholds for the current Vision feature print (iOS 17 and later).
  // These are starting values and should be tuned with real photos; every
  // comparison is logged with its distance to make that easy.
  private static let strongMatch: Float = 0.50
  private static let likelyMatch: Float = 0.75
  private static let weakMatch: Float = 0.95

  static func featurePrint(for image: UIImage) -> VNFeaturePrintObservation? {
    guard let cgImage = image.cgImage else { return nil }
    return featurePrint(with: VNImageRequestHandler(cgImage: cgImage, options: [:]))
  }

  static func featurePrint(at url: URL) -> VNFeaturePrintObservation? {
    featurePrint(with: VNImageRequestHandler(url: url, options: [:]))
  }

  private static func featurePrint(with handler: VNImageRequestHandler) -> VNFeaturePrintObservation? {
    let request = VNGenerateImageFeaturePrintRequest()
    do {
      try handler.perform([request])
      let observation: VNFeaturePrintObservation? = request.results?.first
      return observation
    } catch {
      NSLog("[Match] Could not fingerprint image: %@", error.localizedDescription)
      return nil
    }
  }

  private struct Candidate {
    let name: String
    let photoURLs: [URL]
  }

  private struct Scored {
    let name: String
    let distance: Float
  }

  /// Lines for the AI describing which nearby pack places the camera view resembles.
  /// Empty when there is no frame or no nearby place has reference photos.
  @MainActor
  static func matchLines(frame: UIImage?, latitude: Double, longitude: Double) async -> [String] {
    guard let frame else { return [] }

    let store = PackStore.shared
    var candidates: [Candidate] = []
    for entry in store.places(nearLatitude: latitude, longitude: longitude) {
      let urls = store.photoURLs(packID: entry.packID, placeID: entry.place.id)
      if !urls.isEmpty {
        candidates.append(Candidate(name: entry.place.name, photoURLs: urls))
      }
    }
    guard !candidates.isEmpty else { return [] }

    let knownPrints = store.printCache
    let work = Task.detached(priority: .userInitiated) { () -> (scores: [Scored], newPrints: [String: VNFeaturePrintObservation]) in
      var newPrints: [String: VNFeaturePrintObservation] = [:]
      guard let framePrint = VisualMatcher.featurePrint(for: frame) else {
        return (scores: [], newPrints: newPrints)
      }
      var scores: [Scored] = []
      for candidate in candidates {
        var best: Float?
        for url in candidate.photoURLs {
          var reference = knownPrints[url.path] ?? newPrints[url.path]
          if reference == nil, let computed = VisualMatcher.featurePrint(at: url) {
            newPrints[url.path] = computed
            reference = computed
          }
          guard let referencePrint = reference else { continue }
          var distance = Float(0)
          do {
            try framePrint.computeDistance(&distance, to: referencePrint)
          } catch {
            continue
          }
          if best == nil || distance < (best ?? distance) {
            best = distance
          }
        }
        if let best {
          scores.append(Scored(name: candidate.name, distance: best))
        }
      }
      scores.sort { $0.distance < $1.distance }
      return (scores: scores, newPrints: newPrints)
    }
    let result = await work.value

    for (path, newPrint) in result.newPrints {
      store.printCache[path] = newPrint
    }
    guard let closest = result.scores.first else { return [] }

    for score in result.scores {
      NSLog("[Match] %@ distance %.3f", score.name, score.distance)
    }

    let intro = "Photo match (the camera view compared on the phone with reference photos of \(result.scores.count) nearby place(s)):"
    guard closest.distance <= weakMatch else {
      return [intro, "- The camera view does not closely resemble the reference photos of any of them."]
    }

    var lines = [intro, "- Closest: \(closest.name) (\(label(for: closest.distance)))."]
    if result.scores.count > 1 {
      let second = result.scores[1]
      if second.distance <= weakMatch {
        lines.append("- Next closest: \(second.name) (\(label(for: second.distance))).")
      }
    }
    lines.append("- This is overall visual resemblance, so use it as supporting evidence with location and the written description, not as proof.")
    return lines
  }

  private static func label(for distance: Float) -> String {
    if distance <= strongMatch { return "strong match" }
    if distance <= likelyMatch { return "likely match" }
    return "weak match"
  }
}
