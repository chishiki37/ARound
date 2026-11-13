import Foundation

// MARK: - Tool Call (parsed from server JSON)

struct GeminiFunctionCall {
  let id: String
  let name: String
  let args: [String: Any]
}

struct GeminiToolCall {
  let functionCalls: [GeminiFunctionCall]

  init(functionCalls: [GeminiFunctionCall]) {
    self.functionCalls = functionCalls
  }

  init?(json: [String: Any]) {
    guard let toolCall = json["toolCall"] as? [String: Any],
          let calls = toolCall["functionCalls"] as? [[String: Any]] else {
      return nil
    }
    self.functionCalls = calls.compactMap { call in
      guard let id = call["id"] as? String,
            let name = call["name"] as? String else { return nil }
      let args = call["args"] as? [String: Any] ?? [:]
      return GeminiFunctionCall(id: id, name: name, args: args)
    }
  }
}

// MARK: - Tool Call Cancellation

struct GeminiToolCallCancellation {
  let ids: [String]

  init?(json: [String: Any]) {
    guard let cancellation = json["toolCallCancellation"] as? [String: Any],
          let ids = cancellation["ids"] as? [String] else {
      return nil
    }
    self.ids = ids
  }
}

// MARK: - Tool Result

enum ToolResult {
  case success(String)
  case failure(String)

  var responseValue: [String: Any] {
    switch self {
    case .success(let result):
      return ["result": result]
    case .failure(let error):
      return ["error": error]
    }
  }
}

// MARK: - Tool Call Status (for UI)

enum ToolCallStatus: Equatable {
  case idle
  case executing(String)
  case completed(String)
  case failed(String, String)
  case cancelled(String)

  var displayText: String {
    switch self {
    case .idle: return ""
    case .executing(let name): return "Running: \(name)..."
    case .completed(let name): return "Done: \(name)"
    case .failed(let name, let err): return "Failed: \(name) - \(err)"
    case .cancelled(let name): return "Cancelled: \(name)"
    }
  }

  var isActive: Bool {
    if case .executing = self { return true }
    return false
  }
}

// MARK: - Tool Declarations

/// The only tool the guide has: reading the phone's current GPS position.
/// It is answered on the device; nothing is sent to any other service.
enum ToolDeclarations {
  static let locationToolName = "get_current_location"

  /// Function declarations for the Gemini Live setup message.
  /// Empty when location sharing is turned off in Settings.
  static func allDeclarations() -> [[String: Any]] {
    guard SettingsManager.shared.locationSharingEnabled else { return [] }
    return [getCurrentLocation]
  }

  /// Value for the "tools" field of the Gemini Live setup message.
  static func geminiTools() -> [[String: Any]] {
    let declarations = allDeclarations()
    guard !declarations.isEmpty else { return [] }
    return [["functionDeclarations": declarations]]
  }

  static let getCurrentLocation: [String: Any] = [
    "name": locationToolName,
    "description": "Returns where the wearer is right now from their phone's GPS: coordinates, accuracy in metres, the nearest street address, direction of travel, and a list of named places nearby (landmarks, buildings, shops) with distance, direction and a short Wikipedia summary where available. Call this before identifying a place or landmark, and whenever the wearer asks where they are or what is around them.",
    "behavior": "BLOCKING"
  ]
}
