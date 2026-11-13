import CoreLocation
import MapKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Pack list

/// Lists the guide packs on this phone and lets the wearer add or remove them.
struct PacksView: View {
  @ObservedObject private var store = PackStore.shared
  @State private var showImporter = false
  @State private var showLinkPrompt = false
  @State private var linkText = ""
  @State private var message: String?
  @State private var isDownloading = false

  var body: some View {
    List {
      Section(
        footer: Text("Swipe a pack to remove it. Built-in packs are hidden, not erased, and can be restored.")
      ) {
        if store.packs.isEmpty {
          Text("No packs installed")
            .foregroundColor(.secondary)
        }
        ForEach(store.packs) { pack in
          NavigationLink(destination: PackDetailView(pack: pack)) {
            VStack(alignment: .leading, spacing: 2) {
              Text(pack.name)
              Text(subtitle(for: pack))
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
        }
        .onDelete { offsets in
          let ids = offsets.map { store.packs[$0].id }
          for id in ids {
            store.deletePack(id: id)
          }
        }
      }

      Section(
        header: Text("Add a pack"),
        footer: Text("A pack is a single file ending in .json. Importing a pack with the same name as an existing one replaces it.")
      ) {
        Button("Import from Files") {
          showImporter = true
        }
        Button(isDownloading ? "Downloading…" : "Download from a link") {
          showLinkPrompt = true
        }
        .disabled(isDownloading)
        if store.hasHiddenBuiltIns {
          Button("Restore built-in packs") {
            store.restoreBuiltIns()
          }
        }
      }
    }
    .navigationTitle("Guide Packs")
    .navigationBarTitleDisplayMode(.inline)
    .fileImporter(isPresented: $showImporter, allowedContentTypes: [UTType.json]) { result in
      handleImport(result)
    }
    .alert("Download a pack", isPresented: $showLinkPrompt) {
      TextField("https://", text: $linkText)
      Button("Download") {
        download()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Paste a link to a pack file.")
    }
    .alert("Guide Packs", isPresented: Binding(
      get: { message != nil },
      set: { if !$0 { message = nil } }
    )) {
      Button("OK") { message = nil }
    } message: {
      Text(message ?? "")
    }
  }

  private func subtitle(for pack: GuidePack) -> String {
    var parts = ["\(pack.places.count) places"]
    if !pack.city.isEmpty { parts.append(pack.city) }
    parts.append(store.isBuiltIn(pack.id) ? "Built in" : "Imported")
    return parts.joined(separator: " · ")
  }

  private func handleImport(_ result: Result<URL, Error>) {
    switch result {
    case .success(let url):
      let scoped = url.startAccessingSecurityScopedResource()
      defer {
        if scoped { url.stopAccessingSecurityScopedResource() }
      }
      do {
        let data = try Data(contentsOf: url)
        install(data)
      } catch {
        message = "Could not read that file: \(error.localizedDescription)"
      }
    case .failure(let error):
      message = error.localizedDescription
    }
  }

  private func download() {
    let text = linkText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let url = URL(string: text), url.scheme == "https" else {
      message = "That is not a valid https link."
      return
    }
    isDownloading = true
    Task { @MainActor in
      defer { isDownloading = false }
      do {
        let (data, _) = try await URLSession.shared.data(from: url)
        install(data)
        linkText = ""
      } catch {
        message = "Could not download the pack: \(error.localizedDescription)"
      }
    }
  }

  private func install(_ data: Data) {
    do {
      let pack = try store.importPack(from: data)
      message = "Installed \"\(pack.name)\" with \(pack.places.count) places."
    } catch {
      message = error.localizedDescription
    }
  }
}

// MARK: - One pack

struct PackDetailView: View {
  let pack: GuidePack
  @ObservedObject private var store = PackStore.shared

  var body: some View {
    List {
      Section {
        Map(initialPosition: .automatic) {
          ForEach(pack.places) { place in
            Marker(
              place.name,
              coordinate: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
            )
          }
        }
        .frame(height: 260)
        .listRowInsets(EdgeInsets())
      }

      Section(header: Text("Places, in walking order")) {
        ForEach(pack.orderedPlaces) { place in
          NavigationLink(destination: PlaceDetailView(pack: pack, place: place)) {
            VStack(alignment: .leading, spacing: 2) {
              Text(place.name)
              Text(placeSubtitle(place))
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
        }
      }

      if !pack.attribution.isEmpty {
        Section(header: Text("About this pack")) {
          Text(pack.attribution)
            .font(.footnote)
            .foregroundColor(.secondary)
        }
      }
    }
    .navigationTitle(pack.name)
    .navigationBarTitleDisplayMode(.inline)
  }

  private func placeSubtitle(_ place: GuidePackPlace) -> String {
    // Reading photoRevision keeps the counts fresh after photos change.
    _ = store.photoRevision
    let count = store.photoCount(packID: pack.id, placeID: place.id)
    let photos = count == 1 ? "1 reference photo" : "\(count) reference photos"
    return "\(place.category) · \(photos)"
  }
}

// MARK: - One place

struct PlaceDetailView: View {
  let pack: GuidePack
  let place: GuidePackPlace
  @ObservedObject private var store = PackStore.shared
  @State private var pickerItem: PhotosPickerItem?

  private var photoURLs: [URL] {
    _ = store.photoRevision
    return store.photoURLs(packID: pack.id, placeID: place.id)
  }

  var body: some View {
    List {
      Section(
        header: Text("Reference photos"),
        footer: Text("Photos of this place from the angles you usually see it. The guide compares them with the camera view. Press and hold a photo to delete it. You can also add one from the guide screen while standing in front of the place.")
      ) {
        if photoURLs.isEmpty {
          Text("No reference photos yet")
            .foregroundColor(.secondary)
        } else {
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
              ForEach(photoURLs, id: \.self) { url in
                ReferencePhotoThumbnail(url: url) {
                  store.deletePhoto(url)
                }
              }
            }
            .padding(.vertical, 4)
          }
        }
        PhotosPicker(selection: $pickerItem, matching: .images) {
          Label("Add from photo library", systemImage: "photo.on.rectangle")
        }
      }

      if !place.visualCues.isEmpty {
        Section(header: Text("Looks like")) {
          Text(place.visualCues)
        }
      }

      Section(header: Text("Story")) {
        Text(place.story.isEmpty ? "No story written yet." : place.story)
        if !place.more.isEmpty {
          Text(place.more)
            .foregroundColor(.secondary)
        }
      }

      Section(header: Text("Identifiers")) {
        LabeledContent("Type", value: place.category)
        LabeledContent("Coordinates", value: String(format: "%.5f, %.5f", place.latitude, place.longitude))
        LabeledContent("Viewing distance", value: "\(Int(place.radius)) m")
        if !place.aliases.isEmpty {
          LabeledContent("Also called", value: place.aliases.joined(separator: ", "))
        }
      }

      if !place.sources.isEmpty {
        Section(header: Text("Sources")) {
          ForEach(place.sources, id: \.self) { source in
            Text(source)
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }
      }
    }
    .navigationTitle(place.name)
    .navigationBarTitleDisplayMode(.inline)
    .onChange(of: pickerItem) { item in
      guard let item else { return }
      Task { @MainActor in
        if let data = try? await item.loadTransferable(type: Data.self),
           let image = UIImage(data: data) {
          store.addPhoto(image, packID: pack.id, placeID: place.id)
        }
        pickerItem = nil
      }
    }
  }
}

struct ReferencePhotoThumbnail: View {
  let url: URL
  let onDelete: () -> Void

  var body: some View {
    Group {
      if let image = UIImage(contentsOfFile: url.path) {
        Image(uiImage: image)
          .resizable()
          .scaledToFill()
      } else {
        Color.gray.opacity(0.2)
      }
    }
    .frame(width: 96, height: 96)
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .contextMenu {
      Button("Delete photo", role: .destructive) {
        onDelete()
      }
    }
  }
}

// MARK: - Adding a reference photo from the glasses

/// A camera frame waiting to be filed under a place.
struct ReferenceFrame: Identifiable {
  let id = UUID()
  let image: UIImage
}

/// Shown from the guide screen: files the current glasses frame under a nearby pack place.
struct AddReferencePhotoSheet: View {
  let frame: ReferenceFrame
  @Environment(\.dismiss) private var dismiss
  @State private var savedName: String?

  private var candidates: [NearbyPackPlace] {
    guard let location = LocationManager.shared.lastLocation else { return [] }
    return PackStore.shared.places(
      nearLatitude: location.coordinate.latitude,
      longitude: location.coordinate.longitude
    )
  }

  var body: some View {
    NavigationView {
      List {
        Section {
          Image(uiImage: frame.image)
            .resizable()
            .scaledToFit()
            .frame(maxHeight: 220)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }

        Section(
          header: Text("Which place is this?"),
          footer: Text("The photo is saved on this phone and used to recognise the place next time.")
        ) {
          if candidates.isEmpty {
            Text("No pack places nearby. Reference photos can be added when you are within a few hundred metres of a place in a pack.")
              .foregroundColor(.secondary)
          }
          ForEach(candidates) { entry in
            Button {
              if PackStore.shared.addPhoto(frame.image, packID: entry.packID, placeID: entry.place.id) {
                savedName = entry.place.name
              }
              dismiss()
            } label: {
              VStack(alignment: .leading, spacing: 2) {
                Text(entry.place.name)
                  .foregroundColor(.primary)
                Text("About \(max(10, Int((entry.distance / 10).rounded()) * 10)) m away")
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
            }
          }
        }
      }
      .navigationTitle("Add Reference Photo")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .navigationBarLeading) {
          Button("Cancel") {
            dismiss()
          }
        }
      }
    }
  }
}
