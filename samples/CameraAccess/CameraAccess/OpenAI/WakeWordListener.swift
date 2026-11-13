import AVFoundation
import Foundation
import Speech

/// Listens for the wake phrase while the guide is asleep or muted.
///
/// Uses Apple's on-device speech recognition only: while the guide is asleep,
/// microphone audio stays on the phone and is not sent to the AI provider or to Apple.
/// If on-device recognition is not available, the listener reports itself unavailable
/// and the app falls back to manual unmuting.
///
/// Used from the main thread only.
final class WakeWordListener: @unchecked Sendable {
  /// Called on the main thread when the wake phrase is heard.
  var onWake: (() -> Void)?

  /// True once permission is granted and on-device recognition is supported.
  private(set) var isAvailable = false

  private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var task: SFSpeechRecognitionTask?
  private var lastAttempt = Date.distantPast
  private var wantsListening = false
  private var generation = 0
  private var phrases: [String] = []
  private var hints: [String] = []

  private let format = AVAudioFormat(
    commonFormat: .pcmFormatFloat32,
    sampleRate: 16000,
    channels: 1,
    interleaved: false
  )
  /// Recognition requests are restarted regularly so the transcript stays short.
  private let maxRequestAge: TimeInterval = 45

  // MARK: - Setup

  /// Asks for speech recognition permission (first time only) and checks support.
  func prepare() async {
    let status = await WakeWordListener.requestAuthorization()
    let supportsOnDevice = recognizer?.supportsOnDeviceRecognition ?? false
    isAvailable = status == .authorized && supportsOnDevice
    if !isAvailable {
      NSLog("[Wake] Wake phrase unavailable (authorized: %@, on-device: %@)",
            status == .authorized ? "yes" : "no", supportsOnDevice ? "yes" : "no")
    }
  }

  private static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
    await withCheckedContinuation { continuation in
      SFSpeechRecognizer.requestAuthorization { status in
        continuation.resume(returning: status)
      }
    }
  }

  // MARK: - Listening

  /// Starts listening for any of the given phrases.
  func start(phrases: [String]) {
    guard isAvailable else { return }
    self.hints = phrases
    self.phrases = phrases.map { WakeWordListener.normalized($0) }.filter { !$0.isEmpty }
    wantsListening = true
    beginRequest()
  }

  func stop() {
    wantsListening = false
    generation += 1
    endRequest()
  }

  /// Feeds microphone audio (16 kHz, mono, 16-bit PCM) to the recognizer.
  func append(_ data: Data) {
    guard wantsListening else { return }

    let age = Date().timeIntervalSince(lastAttempt)
    if request == nil {
      // The recognizer was not ready last time; try again every couple of seconds.
      if age > 2 { beginRequest() }
      return
    }
    if age > maxRequestAge {
      beginRequest()
      return
    }

    let sampleCount = data.count / 2
    guard sampleCount > 0,
          let format,
          let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleCount)),
          let channel = buffer.floatChannelData?[0] else {
      return
    }
    data.withUnsafeBytes { rawBuffer in
      let samples = rawBuffer.bindMemory(to: Int16.self)
      for index in 0..<sampleCount {
        channel[index] = Float(samples[index]) / 32768.0
      }
    }
    buffer.frameLength = AVAudioFrameCount(sampleCount)
    request?.append(buffer)
  }

  private func beginRequest() {
    endRequest()
    lastAttempt = Date()
    guard wantsListening, let recognizer, recognizer.isAvailable else { return }

    generation += 1
    let current = generation

    let newRequest = SFSpeechAudioBufferRecognitionRequest()
    newRequest.shouldReportPartialResults = true
    newRequest.requiresOnDeviceRecognition = true
    newRequest.contextualStrings = hints
    request = newRequest

    task = recognizer.recognitionTask(with: newRequest) { [weak self] result, error in
      let text = result?.bestTranscription.formattedString
      let finished = (result?.isFinal ?? false) || error != nil
      DispatchQueue.main.async {
        guard let self, self.generation == current, self.wantsListening else { return }
        if let text, self.matches(text) {
          self.stop()
          self.onWake?()
          return
        }
        if finished {
          // The request ended (silence, time limit or an error). Start a fresh one shortly.
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.generation == current, self.wantsListening else { return }
            self.beginRequest()
          }
        }
      }
    }
  }

  private func endRequest() {
    request?.endAudio()
    task?.cancel()
    request = nil
    task = nil
  }

  // MARK: - Matching

  private func matches(_ transcript: String) -> Bool {
    let heard = " " + WakeWordListener.normalized(transcript) + " "
    for phrase in phrases where heard.contains(" " + phrase + " ") {
      return true
    }
    return false
  }

  /// Lowercased words separated by single spaces, punctuation removed.
  static func normalized(_ text: String) -> String {
    var result = ""
    var lastWasSpace = true
    for scalar in text.lowercased().unicodeScalars {
      if CharacterSet.alphanumerics.contains(scalar) {
        result.unicodeScalars.append(scalar)
        lastWasSpace = false
      } else if !lastWasSpace {
        result.append(" ")
        lastWasSpace = true
      }
    }
    return result.trimmingCharacters(in: .whitespaces)
  }
}
