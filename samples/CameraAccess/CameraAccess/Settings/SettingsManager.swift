import Foundation

final class SettingsManager {
  static let shared = SettingsManager()

  static let defaultOpenAIModel = "gpt-realtime-2.1"

  private let defaults = UserDefaults.standard

  private enum Key: String {
    case geminiAPIKey
    case geminiSystemPrompt
    case selectedModel
    case openAIAPIKey
    case openAIModel
    case webrtcSignalingURL
    case speakerOutputEnabled
    case videoStreamingEnabled
    case locationSharingEnabled
    case autoStartGuide
    case autoSleepEnabled
    case wakePhrase
  }

  private init() {}

  // MARK: - Provider

  /// "gemini" or "openai". Exactly one provider is used per session.
  var selectedModel: String {
    get {
      let value = defaults.string(forKey: Key.selectedModel.rawValue) ?? "gemini"
      return ["gemini", "openai"].contains(value) ? value : "gemini"
    }
    set {
      defaults.set(["gemini", "openai"].contains(newValue) ? newValue : "gemini", forKey: Key.selectedModel.rawValue)
    }
  }

  var geminiAPIKey: String {
    get { defaults.string(forKey: Key.geminiAPIKey.rawValue) ?? Secrets.geminiAPIKey }
    set { defaults.set(newValue, forKey: Key.geminiAPIKey.rawValue) }
  }

  var openAIAPIKey: String {
    get { defaults.string(forKey: Key.openAIAPIKey.rawValue) ?? Secrets.openAIAPIKey }
    set { defaults.set(newValue, forKey: Key.openAIAPIKey.rawValue) }
  }

  /// OpenAI Realtime model name, e.g. "gpt-realtime-2.1".
  var openAIModel: String {
    get {
      let value = (defaults.string(forKey: Key.openAIModel.rawValue) ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
      return value.isEmpty ? SettingsManager.defaultOpenAIModel : value
    }
    set { defaults.set(newValue, forKey: Key.openAIModel.rawValue) }
  }

  // MARK: - Guide

  var geminiSystemPrompt: String {
    get {
      let value = defaults.string(forKey: Key.geminiSystemPrompt.rawValue) ?? ""
      return value.isEmpty ? GeminiConfig.defaultSystemInstruction : value
    }
    set { defaults.set(newValue, forKey: Key.geminiSystemPrompt.rawValue) }
  }

  /// Start the audio guide as soon as the glasses start streaming.
  var autoStartGuide: Bool {
    get { defaults.object(forKey: Key.autoStartGuide.rawValue) as? Bool ?? true }
    set { defaults.set(newValue, forKey: Key.autoStartGuide.rawValue) }
  }

  static let defaultWakePhrase = "Hey ARound"

  /// Stop listening after a quiet spell and wait for the wake phrase.
  var autoSleepEnabled: Bool {
    get { defaults.object(forKey: Key.autoSleepEnabled.rawValue) as? Bool ?? true }
    set { defaults.set(newValue, forKey: Key.autoSleepEnabled.rawValue) }
  }

  /// Seconds without a question before the guide goes to sleep.
  let autoSleepSeconds: TimeInterval = 30

  /// What the wearer says to wake the guide.
  var wakePhrase: String {
    get {
      let value = (defaults.string(forKey: Key.wakePhrase.rawValue) ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
      return value.isEmpty ? SettingsManager.defaultWakePhrase : value
    }
    set { defaults.set(newValue, forKey: Key.wakePhrase.rawValue) }
  }

  /// Send the phone's GPS position to the selected AI provider.
  var locationSharingEnabled: Bool {
    get { defaults.object(forKey: Key.locationSharingEnabled.rawValue) as? Bool ?? true }
    set { defaults.set(newValue, forKey: Key.locationSharingEnabled.rawValue) }
  }

  // MARK: - Audio / Video

  var speakerOutputEnabled: Bool {
    get { defaults.bool(forKey: Key.speakerOutputEnabled.rawValue) }
    set { defaults.set(newValue, forKey: Key.speakerOutputEnabled.rawValue) }
  }

  /// Send glasses camera frames to the AI so it can see what the wearer sees.
  var videoStreamingEnabled: Bool {
    get { defaults.object(forKey: Key.videoStreamingEnabled.rawValue) as? Bool ?? true }
    set { defaults.set(newValue, forKey: Key.videoStreamingEnabled.rawValue) }
  }

  // MARK: - WebRTC

  var webrtcSignalingURL: String {
    get { defaults.string(forKey: Key.webrtcSignalingURL.rawValue) ?? Secrets.webrtcSignalingURL }
    set { defaults.set(newValue, forKey: Key.webrtcSignalingURL.rawValue) }
  }

  // MARK: - Reset

  func resetAll() {
    for key in [Key.geminiAPIKey, .geminiSystemPrompt, .selectedModel,
                .openAIAPIKey, .openAIModel, .webrtcSignalingURL,
                .speakerOutputEnabled, .videoStreamingEnabled,
                .locationSharingEnabled, .autoStartGuide,
                .autoSleepEnabled, .wakePhrase] {
      defaults.removeObject(forKey: key.rawValue)
    }
  }
}
