import Foundation
import UIKit

/// Speech-to-speech guide backed by the OpenAI Realtime API (WebSocket).
///
/// Differences from the Gemini service:
/// - Camera frames are not streamed continuously. The newest frame is kept on the
///   phone and sent together with the GPS position each time the wearer finishes
///   asking something, so every answer is grounded in one fresh image and location.
/// - No tools are declared; location arrives as text with each question.
@MainActor
class OpenAIRealtimeService: NSObject, ObservableObject, VoiceModelService {
  @Published var connectionState: GeminiConnectionState = .disconnected
  @Published var isModelSpeaking: Bool = false

  var onAudioReceived: ((Data) -> Void)?
  var onInterrupted: (() -> Void)?
  var onTurnComplete: (() -> Void)?
  var onInputTranscription: ((String) -> Void)?
  var onOutputTranscription: ((String) -> Void)?
  var onToolCall: ((GeminiToolCall) -> Void)?
  var onToolCallCancellation: ((GeminiToolCallCancellation) -> Void)?
  var onDisconnected: ((String?) -> Void)?

  private var webSocketTask: URLSessionWebSocketTask?
  private var receiveTask: Task<Void, Never>?
  private var connectContinuation: CheckedContinuation<Bool, Never>?
  private var urlSession: URLSession!

  /// 0 = full session config, 1 = without input transcription,
  /// 2 = minimal config (server decides when to answer). Stepped up if the
  /// server rejects a configuration while the session is being set up.
  private var configLevel = 0
  /// True when the app triggers each answer itself after attaching context.
  private var manualResponses = true
  private var responseInProgress = false
  private var receivedInputTranscriptDelta = false

  private var latestFrame: UIImage?
  private var latestFrameTime: Date = .distantPast

  private let micSampleRate: Double = 16000
  private let apiSampleRate: Double = 24000
  private let maxImageDimension: CGFloat = 1024
  private let maxFrameAge: TimeInterval = 5

  override init() {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 30
    super.init()
    self.urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
  }

  func connect() async -> Bool {
    let apiKey = GeminiConfig.openAIAPIKey
    guard GeminiConfig.isOpenAIConfigured else {
      connectionState = .error("OpenAI API key not configured")
      return false
    }

    let model = GeminiConfig.openAIModel
    let escapedModel = model.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? model
    guard let url = URL(string: "wss://api.openai.com/v1/realtime?model=\(escapedModel)") else {
      connectionState = .error("Invalid OpenAI model name: \(model)")
      return false
    }

    connectionState = .connecting
    configLevel = 0
    manualResponses = true

    let result = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
      self.connectContinuation = continuation

      var request = URLRequest(url: url)
      request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

      self.webSocketTask = self.urlSession.webSocketTask(with: request)
      self.webSocketTask?.resume()
      self.startReceiving()

      // Timeout after 15 seconds
      Task {
        try? await Task.sleep(nanoseconds: 15_000_000_000)
        await MainActor.run {
          if self.connectionState == .connecting || self.connectionState == .settingUp {
            self.connectionState = .error("Connection to OpenAI timed out")
          }
          self.resolveConnect(success: false)
        }
      }
    }

    return result
  }

  func disconnect() {
    receiveTask?.cancel()
    receiveTask = nil
    webSocketTask?.cancel(with: .normalClosure, reason: nil)
    webSocketTask = nil
    urlSession.finishTasksAndInvalidate()
    onToolCall = nil
    onToolCallCancellation = nil
    latestFrame = nil
    responseInProgress = false
    connectionState = .disconnected
    isModelSpeaking = false
    resolveConnect(success: false)
  }

  func sendAudio(data: Data) {
    guard connectionState == .ready else { return }
    let resampled = OpenAIRealtimeService.resamplePCM16(data, from: micSampleRate, to: apiSampleRate)
    sendJSON([
      "type": "input_audio_buffer.append",
      "audio": resampled.base64EncodedString()
    ])
  }

  /// Keeps only the newest frame. It is sent with the wearer's next question.
  func sendVideoFrame(image: UIImage) {
    latestFrame = image
    latestFrameTime = Date()
  }

  func sendTextMessage(_ text: String) {
    guard connectionState == .ready else { return }
    sendJSON([
      "type": "conversation.item.create",
      "item": [
        "type": "message",
        "role": "user",
        "content": [
          ["type": "input_text", "text": text]
        ]
      ]
    ])
    sendJSON(["type": "response.create"])
  }

  func sendToolResponse(_ response: [String: Any]) {
    guard let toolResponse = response["toolResponse"] as? [String: Any],
          let functionResponses = toolResponse["functionResponses"] as? [[String: Any]],
          let first = functionResponses.first,
          let callId = first["id"] as? String,
          let responseValue = first["response"] as? [String: Any] else {
      return
    }
    let outputString = jsonString(responseValue) ?? "{}"
    sendJSON([
      "type": "conversation.item.create",
      "item": [
        "type": "function_call_output",
        "call_id": callId,
        "output": outputString
      ]
    ])
    sendJSON(["type": "response.create"])
  }

  // MARK: - Session setup

  private func resolveConnect(success: Bool) {
    if let cont = connectContinuation {
      connectContinuation = nil
      cont.resume(returning: success)
    }
  }

  private func sendSessionUpdate() {
    let pcmFormat: [String: Any] = ["type": "audio/pcm", "rate": 24000]
    var input: [String: Any] = ["format": pcmFormat]
    if configLevel <= 1 {
      // The app attaches the camera frame and GPS position, then asks for the answer itself.
      let turnDetection: [String: Any] = [
        "type": "server_vad",
        "create_response": false,
        "interrupt_response": true
      ]
      input["turn_detection"] = turnDetection
      manualResponses = true
    } else {
      manualResponses = false
    }
    if configLevel == 0 {
      let transcription: [String: Any] = ["model": "gpt-4o-mini-transcribe"]
      input["transcription"] = transcription
    }

    let output: [String: Any] = [
      "format": pcmFormat,
      "voice": "marin"
    ]
    let audio: [String: Any] = [
      "input": input,
      "output": output
    ]
    let session: [String: Any] = [
      "type": "realtime",
      "instructions": GeminiConfig.sessionInstruction,
      "output_modalities": ["audio"],
      "audio": audio
    ]
    NSLog("[OpenAI] Sending session config (level %d)", configLevel)
    sendJSON(["type": "session.update", "session": session])
  }

  /// Adds one user item holding the current GPS position and the newest camera frame.
  private func sendTurnContext() {
    var content: [[String: Any]] = []

    if SettingsManager.shared.locationSharingEnabled {
      content.append([
        "type": "input_text",
        "text": "[Location context] Sent automatically by the phone with this question. Use it silently.\n"
          + LocationManager.shared.contextString()
      ])
    }

    if SettingsManager.shared.videoStreamingEnabled,
       let frame = latestFrame,
       Date().timeIntervalSince(latestFrameTime) <= maxFrameAge,
       let jpeg = downscaled(frame).jpegData(compressionQuality: GeminiConfig.videoJPEGQuality) {
      content.append([
        "type": "input_text",
        "text": "[Camera] What the wearer is looking at right now:"
      ])
      content.append([
        "type": "input_image",
        "image_url": "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
      ])
    }

    guard !content.isEmpty else { return }
    sendJSON([
      "type": "conversation.item.create",
      "item": [
        "type": "message",
        "role": "user",
        "content": content
      ]
    ])
  }

  private func downscaled(_ image: UIImage) -> UIImage {
    let longest = max(image.size.width, image.size.height)
    guard longest > maxImageDimension, longest > 0 else { return image }
    let ratio = maxImageDimension / longest
    let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    return UIGraphicsImageRenderer(size: size, format: format).image { _ in
      image.draw(in: CGRect(origin: .zero, size: size))
    }
  }

  // MARK: - WebSocket plumbing

  private func sendJSON(_ json: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: json),
          let string = String(data: data, encoding: .utf8) else {
      return
    }
    webSocketTask?.send(.string(string)) { _ in }
  }

  private func startReceiving() {
    receiveTask = Task { [weak self] in
      guard let self else { return }
      while !Task.isCancelled {
        guard let task = self.webSocketTask else { break }
        do {
          let message = try await task.receive()
          switch message {
          case .string(let text):
            self.handleMessage(text)
          case .data(let data):
            if let text = String(data: data, encoding: .utf8) {
              self.handleMessage(text)
            }
          @unknown default:
            break
          }
        } catch {
          if !Task.isCancelled {
            let reason = error.localizedDescription
            self.resolveConnect(success: false)
            if case .error = self.connectionState {
              // Keep the more specific error already recorded.
            } else {
              self.connectionState = .disconnected
            }
            self.isModelSpeaking = false
            self.onDisconnected?(reason)
          }
          break
        }
      }
    }
  }

  private func handleMessage(_ text: String) {
    guard let data = text.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let type = json["type"] as? String else {
      return
    }

    switch type {
    case "session.created":
      // Wait for session.updated before marking the session ready.
      break

    case "session.updated":
      if connectionState != .ready {
        connectionState = .ready
        resolveConnect(success: true)
      }

    case "input_audio_buffer.speech_started":
      receivedInputTranscriptDelta = false
      if isModelSpeaking || responseInProgress {
        if responseInProgress {
          sendJSON(["type": "response.cancel"])
        }
        isModelSpeaking = false
        onInterrupted?()
      }
      if !manualResponses {
        sendTurnContext()
      }

    case "input_audio_buffer.committed":
      if manualResponses {
        sendTurnContext()
        sendJSON(["type": "response.create"])
      }

    case "conversation.item.input_audio_transcription.delta":
      if let delta = json["delta"] as? String, !delta.isEmpty {
        receivedInputTranscriptDelta = true
        onInputTranscription?(delta)
      }

    case "conversation.item.input_audio_transcription.completed":
      if !receivedInputTranscriptDelta,
         let transcript = json["transcript"] as? String, !transcript.isEmpty {
        onInputTranscription?(transcript)
      }

    case "response.created":
      responseInProgress = true

    case "response.output_audio.delta", "response.audio.delta":
      if let base64Data = json["delta"] as? String,
         let audioData = Data(base64Encoded: base64Data) {
        if !isModelSpeaking { isModelSpeaking = true }
        onAudioReceived?(audioData)
      }

    case "response.output_audio_transcript.delta", "response.audio_transcript.delta":
      if let delta = json["delta"] as? String {
        onOutputTranscription?(delta)
      }

    case "response.done":
      responseInProgress = false
      isModelSpeaking = false
      if let response = json["response"] as? [String: Any],
         let status = response["status"] as? String, status == "failed" {
        let details = response["status_details"] as? [String: Any]
        let error = details?["error"] as? [String: Any]
        NSLog("[OpenAI] Response failed: %@", (error?["message"] as? String) ?? "unknown reason")
      }
      onTurnComplete?()

    case "error":
      let err = json["error"] as? [String: Any]
      let msg = (err?["message"] as? String) ?? "Unknown OpenAI error"
      NSLog("[OpenAI] Error: %@", msg)
      if connectionState == .settingUp {
        // The session config was rejected. Retry with a simpler one before giving up.
        if configLevel < 2 {
          configLevel += 1
          sendSessionUpdate()
        } else {
          connectionState = .error(msg)
          resolveConnect(success: false)
        }
      }
      // Errors after setup (for example a rejected image) are logged but do not end the session.

    default:
      break
    }
  }

  private func jsonString(_ value: [String: Any]) -> String? {
    guard let data = try? JSONSerialization.data(withJSONObject: value) else { return nil }
    return String(data: data, encoding: .utf8)
  }

  nonisolated private static func resamplePCM16(_ data: Data, from sourceRate: Double, to targetRate: Double) -> Data {
    guard sourceRate != targetRate, !data.isEmpty else { return data }

    let bytesPerSample = 2
    let sampleCount = data.count / bytesPerSample
    guard sampleCount > 0 else { return data }

    let ratio = sourceRate / targetRate
    let outputCount = Int(Double(sampleCount) * (targetRate / sourceRate))
    guard outputCount > 0 else { return data }

    var output = [Int16](repeating: 0, count: outputCount)
    data.withUnsafeBytes { rawBuffer in
      let samples = rawBuffer.bindMemory(to: Int16.self)
      for i in 0..<outputCount {
        let srcPos = Double(i) * ratio
        let idx = Int(srcPos)
        let frac = srcPos - Double(idx)
        let s0 = samples[min(idx, sampleCount - 1)]
        let s1 = samples[min(idx + 1, sampleCount - 1)]
        let val = Double(s0) * (1.0 - frac) + Double(s1) * frac
        output[i] = Int16(max(Double(Int16.min), min(Double(Int16.max), val)))
      }
    }
    return output.withUnsafeBufferPointer { Data(buffer: $0) }
  }
}

// MARK: - URLSessionWebSocketDelegate

extension OpenAIRealtimeService: URLSessionWebSocketDelegate {
  nonisolated func urlSession(
    _ session: URLSession,
    webSocketTask: URLSessionWebSocketTask,
    didOpenWithProtocol protocol: String?
  ) {
    Task { @MainActor [weak self] in
      self?.connectionState = .settingUp
      self?.sendSessionUpdate()
    }
  }

  nonisolated func urlSession(
    _ session: URLSession,
    webSocketTask: URLSessionWebSocketTask,
    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
    reason: Data?
  ) {
    Task { @MainActor [weak self] in
      let reasonStr = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "no reason"
      self?.resolveConnect(success: false)
      self?.connectionState = .disconnected
      self?.isModelSpeaking = false
      self?.onDisconnected?("Connection closed (code \(closeCode.rawValue): \(reasonStr))")
    }
  }

  nonisolated func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: Error?
  ) {
    guard let error else { return }
    Task { @MainActor [weak self] in
      var msg = error.localizedDescription
      if let http = task.response as? HTTPURLResponse {
        switch http.statusCode {
        case 401: msg = "OpenAI rejected the API key (401). Check the key in Settings."
        case 403: msg = "This OpenAI account is not allowed to use the selected model (403)."
        case 404: msg = "OpenAI does not recognise the model name set in Settings (404)."
        case 429: msg = "OpenAI rate limit or quota reached (429). Check billing on your OpenAI account."
        default: break
        }
      }
      self?.resolveConnect(success: false)
      self?.connectionState = .error(msg)
      self?.isModelSpeaking = false
      self?.onDisconnected?(msg)
    }
  }
}
