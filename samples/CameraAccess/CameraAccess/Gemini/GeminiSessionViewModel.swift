import Foundation
import SwiftUI

// MARK: - Protocol that lets us swap the voice model (Gemini or OpenAI) at runtime.

@MainActor
protocol VoiceModelService: AnyObject {
  var connectionState: GeminiConnectionState { get }
  var isModelSpeaking: Bool { get }

  func connect() async -> Bool
  func disconnect()
  func sendAudio(data: Data)
  func sendVideoFrame(image: UIImage)
  func sendTextMessage(_ text: String)
  func sendToolResponse(_ response: [String: Any])

  var onAudioReceived: ((Data) -> Void)? { get set }
  var onInterrupted: (() -> Void)? { get set }
  var onTurnComplete: (() -> Void)? { get set }
  var onInputTranscription: ((String) -> Void)? { get set }
  var onOutputTranscription: ((String) -> Void)? { get set }
  var onToolCall: ((GeminiToolCall) -> Void)? { get set }
  var onToolCallCancellation: ((GeminiToolCallCancellation) -> Void)? { get set }
  var onDisconnected: ((String?) -> Void)? { get set }
}

extension GeminiLiveService: VoiceModelService {}

/// Runs one audio-guide session: microphone in, spoken answers out, with camera
/// frames and GPS position passed to the selected provider (Gemini or OpenAI).
@MainActor
class GeminiSessionViewModel: ObservableObject {
  @Published var isGeminiActive: Bool = false
  @Published var connectionState: GeminiConnectionState = .disconnected
  @Published var isModelSpeaking: Bool = false
  @Published var errorMessage: String?
  @Published var userTranscript: String = ""
  @Published var aiTranscript: String = ""
  @Published var toolCallStatus: ToolCallStatus = .idle
  @Published var locationStatus: String = ""
  @Published var hasGoodLocationFix: Bool = false

  private var voiceService: VoiceModelService?
  private let audioManager = AudioManager()
  private var lastVideoFrameTime: Date = .distantPast
  private var stateObservation: Task<Void, Never>?

  // Providers end long sessions on their own (Gemini Live closes after roughly ten
  // minutes). Reconnect quietly so a walk is not interrupted by an error alert.
  private var sessionReadyAt: Date?
  private var reconnectAttempts = 0
  private let maxReconnectAttempts = 3
  private var sessionGeneration = 0

  var streamingMode: StreamingMode = .glasses

  /// True while the guide is not hearing the wearer: asleep after a quiet spell,
  /// or muted by voice or the mic button. The phone listens for the wake phrase.
  @Published var isMicMuted: Bool = false
  /// True while the wearer has paused the glasses with a tap on the temple.
  /// Nothing is listened to at all until they tap again.
  @Published var isPausedByGlasses: Bool = false

  private let wakeListener = WakeWordListener()
  /// The last few seconds of audio heard while asleep, so a question asked in the
  /// same breath as the wake phrase is not cut off.
  private var wakeBuffer: [Data] = []
  private let wakeBufferChunks = 50  // about 5 seconds
  private var lastActivity = Date()

  /// Short label for the listening state shown on the guide screen.
  var listeningStatus: String {
    if isPausedByGlasses { return "Paused · tap glasses" }
    if isMicMuted {
      return wakeListener.isAvailable
        ? "Asleep · say \"\(SettingsManager.shared.wakePhrase)\""
        : "Muted"
    }
    return "Listening"
  }

  func toggleMicMute() {
    if isMicMuted {
      wakeUp(flushBuffer: false)
    } else {
      goToSleep()
    }
  }

  /// Called when the glasses stream is paused or resumed by a tap on the temple.
  func setPausedByGlasses(_ paused: Bool) {
    guard paused != isPausedByGlasses else { return }
    isPausedByGlasses = paused
    guard isGeminiActive else { return }
    if paused {
      wakeListener.stop()
      wakeBuffer.removeAll()
      audioManager.stopPlayback()
      NSLog("[ARound] Paused from the glasses")
    } else {
      NSLog("[ARound] Resumed from the glasses")
      wakeUp(flushBuffer: false)
    }
  }

  /// Stops sending audio to the guide and starts listening for the wake phrase on the phone.
  private func goToSleep() {
    guard isGeminiActive, !isMicMuted else { return }
    isMicMuted = true
    wakeBuffer.removeAll()
    audioManager.stopPlayback()
    playChime(frequency: 440)
    if !isPausedByGlasses {
      wakeListener.start(phrases: wakePhrases)
    }
    NSLog("[ARound] Guide asleep")
  }

  /// Starts sending audio to the guide again.
  private func wakeUp(flushBuffer: Bool) {
    guard isGeminiActive else { return }
    wakeListener.stop()
    let buffered = wakeBuffer
    wakeBuffer.removeAll()
    isMicMuted = false
    lastActivity = Date()
    playChime(frequency: 880)
    if flushBuffer {
      for chunk in buffered {
        voiceService?.sendAudio(data: chunk)
      }
    }
    NSLog("[ARound] Guide awake")
  }

  private var wakePhrases: [String] {
    [SettingsManager.shared.wakePhrase, "hey around", "hey a round", "unmute", "un mute", "on mute", "wake up"]
  }

  /// A short, soft tone through the glasses: higher for awake, lower for asleep.
  private func playChime(frequency: Double) {
    let sampleRate = GeminiConfig.outputAudioSampleRate
    let frameCount = Int(sampleRate * 0.14)
    var samples = [Int16](repeating: 0, count: frameCount)
    for index in 0..<frameCount {
      let progress = Double(index) / Double(frameCount)
      let envelope = sin(progress * Double.pi)
      let value = sin(2.0 * Double.pi * frequency * Double(index) / sampleRate) * envelope * 0.25
      samples[index] = Int16(value * Double(Int16.max))
    }
    let data = samples.withUnsafeBufferPointer { Data(buffer: $0) }
    audioManager.playAudio(data: data)
  }

  /// Handles voice commands like "mute the mic", "unmute my microphone" etc.
  /// Returns true if a command was recognized and handled.
  private func handleVoiceMuteCommand(_ text: String) -> Bool {
    let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    let mutePhrases = ["mute my mic", "mute the mic", "mute microphone", "turn off my mic", "turn off the mic", "mute mic", "go to sleep", "stop listening"]
    let unmutePhrases = ["unmute my mic", "unmute the mic", "unmute microphone", "turn on my mic", "turn on the mic", "unmute mic"]

    // Check "unmute" first: every unmute phrase also contains a mute phrase.
    for phrase in unmutePhrases {
      if lower.contains(phrase) {
        if isMicMuted {
          wakeUp(flushBuffer: false)
          NSLog("[ARound] Voice command: unmuted mic")
        }
        return true
      }
    }

    for phrase in mutePhrases {
      if lower.contains(phrase) {
        if !isMicMuted {
          goToSleep()
          NSLog("[ARound] Voice command: muted mic")
        }
        return true
      }
    }

    return false
  }

  func startSession() async {
    guard !isGeminiActive else { return }

    let useOpenAI = GeminiConfig.selectedModel == "openai"
    let modelName = useOpenAI ? "OpenAI" : "Gemini"
    let isConfigured = useOpenAI ? GeminiConfig.isOpenAIConfigured : GeminiConfig.isConfigured

    guard isConfigured else {
      errorMessage = "\(modelName) is not configured. Open Settings and add your \(modelName) API key."
      return
    }

    isGeminiActive = true

    // Start GPS before connecting so the first answer already knows where we are.
    LocationManager.shared.start()

    // Exactly one provider per session.
    let service: VoiceModelService = useOpenAI ? OpenAIRealtimeService() : GeminiLiveService()
    self.voiceService = service

    // Wire audio callbacks
    audioManager.onAudioCaptured = { [weak self] data in
      guard let self else { return }
      Task { @MainActor in
        // Paused from the glasses: nothing listens at all.
        if self.isPausedByGlasses { return }
        // Asleep or muted: the audio stays on the phone, heard only by the wake-phrase listener.
        if self.isMicMuted {
          self.wakeListener.append(data)
          self.wakeBuffer.append(data)
          if self.wakeBuffer.count > self.wakeBufferChunks {
            self.wakeBuffer.removeFirst(self.wakeBuffer.count - self.wakeBufferChunks)
          }
          return
        }
        // When the answer plays through the phone speaker, mute the mic while the
        // guide is talking so it does not hear itself.
        if SettingsManager.shared.speakerOutputEnabled
            && (self.voiceService?.isModelSpeaking == true || self.audioManager.isPlayingTTS) {
          return
        }
        self.voiceService?.sendAudio(data: data)
      }
    }

    service.onAudioReceived = { [weak self] data in
      self?.lastActivity = Date()
      self?.audioManager.playAudio(data: data)
    }

    wakeListener.onWake = { [weak self] in
      self?.wakeUp(flushBuffer: true)
    }

    service.onInterrupted = { [weak self] in
      self?.audioManager.stopPlayback()
    }

    service.onTurnComplete = { [weak self] in
      guard let self else { return }
      Task { @MainActor in
        // Clear user transcript when the guide finishes responding
        self.userTranscript = ""
        self.lastActivity = Date()
      }
    }

    service.onInputTranscription = { [weak self] text in
      guard let self else { return }
      Task { @MainActor in
        if self.handleVoiceMuteCommand(text) {
          self.userTranscript = ""
          return
        }
        self.userTranscript += text
        self.aiTranscript = ""
        self.lastActivity = Date()
      }
    }

    service.onOutputTranscription = { [weak self] text in
      guard let self else { return }
      Task { @MainActor in
        self.aiTranscript += text
      }
    }

    // Handle unexpected disconnection
    service.onDisconnected = { [weak self] reason in
      guard let self else { return }
      Task { @MainActor in
        // While a session is still starting, startSession() reports the failure itself.
        guard self.isGeminiActive, let readyAt = self.sessionReadyAt else { return }
        // A session that ran for a while earns a fresh set of reconnect attempts.
        if Date().timeIntervalSince(readyAt) > 60 {
          self.reconnectAttempts = 0
        }
        self.teardown()
        if self.reconnectAttempts < self.maxReconnectAttempts {
          self.reconnectAttempts += 1
          let generation = self.sessionGeneration
          NSLog("[ARound] Guide connection ended (%@). Reconnecting, attempt %d", reason ?? "unknown", self.reconnectAttempts)
          try? await Task.sleep(nanoseconds: 1_000_000_000)
          // Do not reconnect if the wearer stopped the guide in the meantime.
          guard generation == self.sessionGeneration, !self.isGeminiActive else { return }
          await self.startSession()
        } else {
          self.errorMessage = "Connection lost: \(reason ?? "Unknown error")"
        }
      }
    }

    // The only tool is the on-device location lookup.
    service.onToolCall = { [weak self] toolCall in
      guard let self else { return }
      Task { @MainActor in
        for call in toolCall.functionCalls {
          self.handleToolCall(call)
        }
      }
    }

    // Observe service and location state
    stateObservation = Task { [weak self] in
      guard let self else { return }
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        guard !Task.isCancelled else { break }
        let newState = self.voiceService?.connectionState ?? .disconnected
        if self.connectionState != newState { self.connectionState = newState }
        let speaking = self.voiceService?.isModelSpeaking ?? false
        if self.isModelSpeaking != speaking { self.isModelSpeaking = speaking }
        let location = LocationManager.shared.statusText
        if self.locationStatus != location { self.locationStatus = location }
        let goodFix = LocationManager.shared.hasGoodFix
        if self.hasGoodLocationFix != goodFix { self.hasGoodLocationFix = goodFix }

        // Go to sleep after a quiet spell, but only if the wake phrase can bring us back.
        if SettingsManager.shared.autoSleepEnabled,
           self.wakeListener.isAvailable,
           self.sessionReadyAt != nil,
           !self.isMicMuted,
           !self.isPausedByGlasses,
           !speaking,
           !self.audioManager.isPlayingTTS,
           Date().timeIntervalSince(self.lastActivity) > SettingsManager.shared.autoSleepSeconds {
          self.goToSleep()
        }
      }
    }

    // Setup audio
    do {
      try audioManager.setupAudioSession(useIPhoneMode: false, forceCommunicationMode: false)
    } catch {
      errorMessage = "Audio setup failed: \(error.localizedDescription)"
      endFailedStart(service: service)
      return
    }

    // Connect to the selected provider and wait until it is ready
    let setupOk = await service.connect()

    if !setupOk {
      let msg: String
      if case .error(let err) = service.connectionState {
        msg = err
      } else {
        msg = "Failed to connect to \(modelName)"
      }
      errorMessage = msg
      endFailedStart(service: service)
      return
    }

    // Start mic capture
    do {
      try audioManager.startCapture()
    } catch {
      errorMessage = "Mic capture failed: \(error.localizedDescription)"
      endFailedStart(service: service)
      return
    }

    // Ask for speech recognition permission (first run) so the wake phrase can work.
    await wakeListener.prepare()

    lastActivity = Date()
    sessionReadyAt = Date()
  }

  private func endFailedStart(service: VoiceModelService) {
    service.disconnect()
    voiceService = nil
    stateObservation?.cancel()
    stateObservation = nil
    LocationManager.shared.stop()
    isGeminiActive = false
    connectionState = .disconnected
  }

  /// Stops the guide on purpose (button, or the glasses stream ended).
  func stopSession() {
    sessionGeneration += 1
    reconnectAttempts = 0
    teardown()
  }

  private func teardown() {
    audioManager.stopCapture()
    voiceService?.onDisconnected = nil
    voiceService?.disconnect()
    voiceService = nil
    stateObservation?.cancel()
    stateObservation = nil
    LocationManager.shared.stop()
    sessionReadyAt = nil
    wakeListener.stop()
    wakeBuffer.removeAll()
    isMicMuted = false
    isGeminiActive = false
    connectionState = .disconnected
    isModelSpeaking = false
    userTranscript = ""
    aiTranscript = ""
    toolCallStatus = .idle
  }

  /// The newest camera frame, kept for photo matching.
  private var latestFrame: UIImage?

  func sendVideoFrameIfThrottled(image: UIImage) {
    latestFrame = image
    guard SettingsManager.shared.videoStreamingEnabled else { return }
    guard isGeminiActive, connectionState == .ready else { return }
    // Asleep, muted or paused: the guide sees nothing either.
    guard !isMicMuted, !isPausedByGlasses else { return }
    let now = Date()
    guard now.timeIntervalSince(lastVideoFrameTime) >= GeminiConfig.videoFrameInterval else { return }
    lastVideoFrameTime = now
    voiceService?.sendVideoFrame(image: image)
  }

  // MARK: - Tools

  private func handleToolCall(_ call: GeminiFunctionCall) {
    if call.name == ToolDeclarations.locationToolName {
      Task { @MainActor in
        // Give the nearby-places lookup a moment to finish so the answer is current.
        var matchLines: [String] = []
        if let location = LocationManager.shared.lastLocation {
          await NearbyPlacesService.shared.refreshAndWait(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            timeout: 2.5
          )
          // Compare the camera view with reference photos of nearby pack places.
          matchLines = await VisualMatcher.matchLines(
            frame: self.latestFrame,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
          )
        }
        var text = LocationManager.shared.contextString()
        if !matchLines.isEmpty {
          text += "\n\n" + matchLines.joined(separator: "\n")
        }
        self.sendToolResult(.success(text), for: call)
      }
    } else {
      sendToolResult(.failure("Unknown tool: \(call.name)"), for: call)
    }
  }

  private func sendToolResult(_ result: ToolResult, for call: GeminiFunctionCall) {
    let response: [String: Any] = [
      "toolResponse": [
        "functionResponses": [
          [
            "id": call.id,
            "name": call.name,
            "response": result.responseValue
          ]
        ]
      ]
    ]
    voiceService?.sendToolResponse(response)
  }
}
