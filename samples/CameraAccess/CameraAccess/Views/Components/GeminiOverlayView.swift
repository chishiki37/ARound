import SwiftUI

struct GeminiStatusBar: View {
  @ObservedObject var geminiVM: GeminiSessionViewModel
  private let settings = SettingsManager.shared

  var body: some View {
    HStack(spacing: 8) {
      // Provider connection pill
      StatusPill(color: geminiStatusColor, text: geminiStatusText)

      // GPS pill
      if !geminiVM.locationStatus.isEmpty {
        StatusPill(color: geminiVM.hasGoodLocationFix ? .green : .yellow, text: geminiVM.locationStatus)
      }
    }
  }


  private var modelName: String {
    settings.selectedModel == "openai" ? "OpenAI" : "Gemini"
  }

  private var geminiStatusColor: Color {
    switch geminiVM.connectionState {
    case .ready: return .green
    case .connecting, .settingUp: return .yellow
    case .error: return .red
    case .disconnected: return .gray
    }
  }

  private var geminiStatusText: String {
    switch geminiVM.connectionState {
    case .ready: return modelName
    case .connecting, .settingUp: return "\(modelName)..."
    case .error: return "\(modelName) Error"
    case .disconnected: return "\(modelName) Off"
    }
  }
}

struct StatusPill: View {
  let color: Color
  let text: String

  var body: some View {
    HStack(spacing: 6) {
      Circle()
        .fill(color)
        .frame(width: 8, height: 8)
      Text(text)
        .font(ARTheme.display(12, weight: .medium))
        .foregroundColor(ARTheme.ink)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .background(ARTheme.bubble)
    .cornerRadius(16)
    .arFloat()
  }
}

struct TranscriptView: View {
  let userText: String
  let aiText: String

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      if !userText.isEmpty {
        Text(userText)
          .font(ARTheme.body(14))
          .foregroundColor(ARTheme.inkSoft)
      }
      if !aiText.isEmpty {
        Text(aiText)
          .font(ARTheme.display(17, weight: .medium))
          .foregroundColor(ARTheme.ink)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .background(ARTheme.bubble)
    .cornerRadius(20)
    .arFloat()
  }
}

struct ToolCallStatusView: View {
  let status: ToolCallStatus

  var body: some View {
    if status != .idle {
      HStack(spacing: 8) {
        statusIcon
        Text(status.displayText)
          .font(.system(size: 13, weight: .medium))
          .foregroundColor(.white)
          .lineLimit(1)
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 8)
      .background(statusBackground)
      .cornerRadius(16)
    }
  }

  @ViewBuilder
  private var statusIcon: some View {
    switch status {
    case .executing:
      ProgressView()
        .scaleEffect(0.7)
        .tint(.white)
    case .completed:
      Image(systemName: "checkmark.circle.fill")
        .foregroundColor(.green)
        .font(.system(size: 14))
    case .failed:
      Image(systemName: "exclamationmark.circle.fill")
        .foregroundColor(.red)
        .font(.system(size: 14))
    case .cancelled:
      Image(systemName: "xmark.circle.fill")
        .foregroundColor(.yellow)
        .font(.system(size: 14))
    case .idle:
      EmptyView()
    }
  }

  private var statusBackground: Color {
    switch status {
    case .executing: return Color.black.opacity(0.7)
    case .completed: return Color.black.opacity(0.6)
    case .failed: return Color.red.opacity(0.3)
    case .cancelled: return Color.black.opacity(0.6)
    case .idle: return Color.clear
    }
  }
}

struct SpeakingIndicator: View {
  @State private var animating = false

  var body: some View {
    HStack(spacing: 3) {
      ForEach(0..<4, id: \.self) { index in
        RoundedRectangle(cornerRadius: 1.5)
          .fill(ARTheme.coral)
          .frame(width: 3, height: animating ? CGFloat.random(in: 8...20) : 6)
          .animation(
            .easeInOut(duration: 0.3)
              .repeatForever(autoreverses: true)
              .delay(Double(index) * 0.1),
            value: animating
          )
      }
    }
    .onAppear { animating = true }
    .onDisappear { animating = false }
  }
}

/// Shows whether the guide is listening, asleep (waiting for the wake phrase) or paused.
struct ListeningPill: View {
  @ObservedObject var geminiVM: GeminiSessionViewModel

  var body: some View {
    StatusPill(color: pillColor, text: geminiVM.listeningStatus)
  }

  private var pillColor: Color {
    if geminiVM.isPausedByGlasses { return .gray }
    return geminiVM.isMicMuted ? ARTheme.grape : .green
  }
}
