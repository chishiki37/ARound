import SwiftUI

struct SettingsView: View {
  @Environment(\.dismiss) private var dismiss
  @ObservedObject var wearablesViewModel: WearablesViewModel
  private let settings = SettingsManager.shared
  @ObservedObject private var packStore = PackStore.shared

  // Provider (exactly one is used per session)
  @State private var selectedModel: String = "gemini"
  @State private var geminiAPIKey: String = ""
  @State private var openAIAPIKey: String = ""
  @State private var openAIModel: String = ""

  // Guide behaviour
  @State private var autoStartGuide: Bool = true
  @State private var locationSharingEnabled: Bool = true
  @State private var videoStreamingEnabled: Bool = true
  @State private var speakerOutputEnabled: Bool = false
  @State private var autoSleepEnabled: Bool = true
  @State private var wakePhrase: String = ""

  // Advanced
  @State private var geminiSystemPrompt: String = ""
  @State private var webrtcSignalingURL: String = ""
  @State private var showResetConfirmation = false

  var body: some View {
    NavigationView {
      Form {
        statusSummarySection
        glassesSection
        providerSection
        guideSection
        listeningSection
        packsSection
        advancedSection
        dangerZoneSection
      }
      .navigationTitle("Settings")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .navigationBarLeading) {
          Button("Cancel") {
            dismiss()
          }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
          Button("Save") {
            save()
            dismiss()
          }
          .fontWeight(.semibold)
        }
      }
      .alert("Reset Settings", isPresented: $showResetConfirmation) {
        Button("Reset", role: .destructive) {
          settings.resetAll()
          loadCurrentValues()
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("This will reset all settings to the values built into the app.")
      }
      .onAppear {
        loadCurrentValues()
      }
    }
  }

  // MARK: - Sections

  private var statusSummarySection: some View {
    Section {
      HStack(spacing: 8) {
        StatusChip(
          label: "Glasses",
          status: wearablesViewModel.glassesStatus.rawValue,
          color: glassesStatusColor
        )
        StatusChip(
          label: "Provider",
          status: providerStatusText,
          color: providerStatusColor
        )
        StatusChip(
          label: "Location",
          status: locationStatusText,
          color: locationStatusColor
        )
      }
      .padding(.vertical, 4)
    }
  }

  private var glassesSection: some View {
    Section(
      header: Text("Glasses"),
      footer: Text("Connect your Meta Ray-Ban glasses so the guide can see and speak.")
    ) {
      HStack {
        Text("Status")
          .font(.system(size: 15))
        Spacer()
        Text(wearablesViewModel.glassesStatus.rawValue)
          .font(.system(size: 15, weight: .semibold))
          .foregroundColor(glassesStatusColor)
      }

      switch wearablesViewModel.glassesStatus {
      case .notRegistered:
        Button("Connect Glasses") {
          wearablesViewModel.connectGlasses()
        }
      case .registered, .connected:
        Button("Disconnect Glasses", role: .destructive) {
          wearablesViewModel.disconnectGlasses()
        }
      }
    }
  }

  private var providerSection: some View {
    Section(
      header: Text("AI Provider"),
      footer: Text(providerFooter)
    ) {
      Picker("Provider", selection: $selectedModel) {
        Text("Gemini Live").tag("gemini")
        Text("OpenAI").tag("openai")
      }
      .pickerStyle(SegmentedPickerStyle())

      if selectedModel == "openai" {
        SecureInputField(
          title: "OpenAI API Key",
          placeholder: "sk-...",
          text: $openAIAPIKey
        )

        VStack(alignment: .leading, spacing: 4) {
          Text("Realtime model")
            .font(.caption)
            .foregroundColor(.secondary)
          TextField(SettingsManager.defaultOpenAIModel, text: $openAIModel)
            .autocapitalization(.none)
            .disableAutocorrection(true)
            .font(.system(.body, design: .monospaced))
        }
      } else {
        SecureInputField(
          title: "Gemini API Key",
          placeholder: "Enter Gemini API key",
          text: $geminiAPIKey
        )
      }
    }
  }

  private var providerFooter: String {
    if selectedModel == "openai" {
      return "Uses the OpenAI Realtime API, billed to your OpenAI account. Create a key at platform.openai.com under API keys. The model must be a Realtime model that accepts images."
    }
    return "Uses the Gemini Live API. One provider is used at a time; switch here whenever you like."
  }

  private var guideSection: some View {
    Section(
      header: Text("Audio Guide"),
      footer: Text("While the guide is on, your location and camera frames go to the selected AI provider. Your coordinates are also sent to Apple Maps and Wikipedia to look up nearby places.")
    ) {
      Toggle("Start guide automatically", isOn: $autoStartGuide)
      Toggle("Share location with guide", isOn: $locationSharingEnabled)
      Toggle("Let guide see camera", isOn: $videoStreamingEnabled)
      Toggle("Play through phone speaker", isOn: $speakerOutputEnabled)
    }
  }

  private var listeningSection: some View {
    Section(
      header: Text("Listening"),
      footer: Text("When asleep or muted, the guide hears nothing. Your phone listens for the wake phrase on its own, and that audio never leaves it. Tapping the side of your glasses pauses the guide completely; tap again to resume.")
    ) {
      Toggle("Sleep after 30 seconds of quiet", isOn: $autoSleepEnabled)

      VStack(alignment: .leading, spacing: 4) {
        Text("Wake phrase")
          .font(.caption)
          .foregroundColor(.secondary)
        TextField(SettingsManager.defaultWakePhrase, text: $wakePhrase)
          .disableAutocorrection(true)
      }
    }
  }

  private var packsSection: some View {
    Section(
      header: Text("Guide Packs"),
      footer: Text("Curated places with checked stories and reference photos. Packs work without a connection and are used before the live lookup.")
    ) {
      NavigationLink(destination: PacksView()) {
        HStack {
          Text("Manage packs")
          Spacer()
          Text("\(packStore.packs.count) installed")
            .foregroundColor(.secondary)
        }
      }
    }
  }

  private var advancedSection: some View {
    Section(header: Text("Advanced")) {
      DisclosureGroup("Guide instructions") {
        TextEditor(text: $geminiSystemPrompt)
          .font(.system(.body, design: .monospaced))
          .frame(minHeight: 160)
        Button("Restore default instructions") {
          geminiSystemPrompt = GeminiConfig.defaultSystemInstruction
        }
      }

      DisclosureGroup("Live streaming (WebRTC)") {
        VStack(alignment: .leading, spacing: 4) {
          Text("Signaling URL")
            .font(.caption)
            .foregroundColor(.secondary)
          TextField("wss://your-server.example.com", text: $webrtcSignalingURL)
            .autocapitalization(.none)
            .disableAutocorrection(true)
            .keyboardType(.URL)
            .font(.system(.body, design: .monospaced))
        }
      }
    }
  }

  private var dangerZoneSection: some View {
    Section(
      header: Text("Danger Zone"),
      footer: Text("This will erase API keys and preferences entered on this screen.")
    ) {
      Button("Reset to Defaults", role: .destructive) {
        showResetConfirmation = true
      }
    }
  }

  // MARK: - Status helpers

  private var glassesStatusColor: Color {
    switch wearablesViewModel.glassesStatus {
    case .connected: return .green
    case .registered: return .orange
    case .notRegistered: return .red
    }
  }

  private var providerStatusText: String {
    let key = (selectedModel == "openai" ? openAIAPIKey : geminiAPIKey)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let placeholder = selectedModel == "openai" ? "YOUR_OPENAI_API_KEY" : "YOUR_GEMINI_API_KEY"
    return (!key.isEmpty && key != placeholder) ? "Configured" : "Missing key"
  }

  private var providerStatusColor: Color {
    providerStatusText == "Configured" ? .green : .red
  }

  private var locationStatusText: String {
    if !locationSharingEnabled { return "Off" }
    if LocationManager.shared.isDenied { return "No access" }
    return LocationManager.shared.isAuthorized ? "On" : "Not asked"
  }

  private var locationStatusColor: Color {
    switch locationStatusText {
    case "On": return .green
    case "Off", "Not asked": return .orange
    default: return .red
    }
  }

  // MARK: - Persistence

  private func loadCurrentValues() {
    selectedModel = settings.selectedModel
    geminiAPIKey = settings.geminiAPIKey
    openAIAPIKey = settings.openAIAPIKey
    openAIModel = settings.openAIModel

    autoStartGuide = settings.autoStartGuide
    locationSharingEnabled = settings.locationSharingEnabled
    videoStreamingEnabled = settings.videoStreamingEnabled
    speakerOutputEnabled = settings.speakerOutputEnabled
    autoSleepEnabled = settings.autoSleepEnabled
    wakePhrase = settings.wakePhrase

    geminiSystemPrompt = settings.geminiSystemPrompt
    webrtcSignalingURL = settings.webrtcSignalingURL
  }

  private func save() {
    settings.selectedModel = selectedModel
    settings.geminiAPIKey = geminiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
    settings.openAIAPIKey = openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
    settings.openAIModel = openAIModel.trimmingCharacters(in: .whitespacesAndNewlines)

    settings.autoStartGuide = autoStartGuide
    settings.locationSharingEnabled = locationSharingEnabled
    settings.videoStreamingEnabled = videoStreamingEnabled
    settings.speakerOutputEnabled = speakerOutputEnabled
    settings.autoSleepEnabled = autoSleepEnabled
    settings.wakePhrase = wakePhrase.trimmingCharacters(in: .whitespacesAndNewlines)

    // Store nothing when the instructions are unchanged, so future app updates
    // to the built-in instructions still apply.
    let prompt = geminiSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
    let builtIn = GeminiConfig.defaultSystemInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
    settings.geminiSystemPrompt = (prompt == builtIn) ? "" : prompt
    settings.webrtcSignalingURL = webrtcSignalingURL.trimmingCharacters(in: .whitespacesAndNewlines)

    if locationSharingEnabled {
      LocationManager.shared.prepare()
    }
  }
}

// MARK: - Reusable components

struct StatusChip: View {
  let label: String
  let status: String
  let color: Color

  var body: some View {
    VStack(spacing: 2) {
      Text(label)
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(.secondary)
      Text(status)
        .font(.system(size: 12, weight: .semibold))
        .foregroundColor(color)
        .lineLimit(1)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 8)
    .background(Color(.systemGray6))
    .cornerRadius(10)
  }
}

struct SecureInputField: View {
  let title: String
  let placeholder: String
  @Binding var text: String
  var keyboardType: UIKeyboardType = .default

  @State private var isVisible = false

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.caption)
        .foregroundColor(.secondary)

      HStack(spacing: 8) {
        Group {
          if isVisible {
            TextField(placeholder, text: $text)
          } else {
            SecureField(placeholder, text: $text)
          }
        }
        .autocapitalization(.none)
        .disableAutocorrection(true)
        .font(.system(.body, design: .monospaced))
        .keyboardType(keyboardType)

        Button {
          isVisible.toggle()
        } label: {
          Image(systemName: isVisible ? "eye.slash" : "eye")
            .foregroundColor(.secondary)
            .frame(width: 24, height: 24)
        }
        .accessibilityLabel(isVisible ? "Hide \(title)" : "Show \(title)")
      }
    }
  }
}
