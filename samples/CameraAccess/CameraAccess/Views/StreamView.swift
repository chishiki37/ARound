/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// StreamView.swift
//
// Main UI for video streaming from Meta wearable devices using the DAT SDK.
// This view demonstrates the complete streaming API: video streaming with real-time display, photo capture,
// and error handling. Extended with Gemini Live AI assistant and WebRTC live streaming integration.
//

import MWDATCore
import SwiftUI

struct StreamView: View {
  @ObservedObject var viewModel: StreamSessionViewModel
  @ObservedObject var wearablesVM: WearablesViewModel
  @ObservedObject var geminiVM: GeminiSessionViewModel
  @ObservedObject var webrtcVM: WebRTCSessionViewModel
  @State private var referenceFrame: ReferenceFrame?

  /// True when a place from a guide pack is close enough to photograph.
  private var hasPackPlaceNearby: Bool {
    guard let location = LocationManager.shared.lastLocation else { return false }
    return !PackStore.shared.places(
      nearLatitude: location.coordinate.latitude,
      longitude: location.coordinate.longitude
    ).isEmpty
  }

  var body: some View {
    ZStack {
      // Cream canvas behind the camera view
      ARBackground()

      // Video backdrop: PiP when WebRTC connected, otherwise single local feed
      if webrtcVM.isActive && webrtcVM.connectionState == .connected {
        PiPVideoView(
          localFrame: viewModel.currentVideoFrame,
          remoteVideoTrack: webrtcVM.remoteVideoTrack,
          hasRemoteVideo: webrtcVM.hasRemoteVideo
        )
      } else if viewModel.streamingMode == .audioOnly {
        VStack(spacing: 16) {
          Image(systemName: "waveform")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 80, height: 80)
            .foregroundColor(.white.opacity(0.4))
          Text("Audio Only Mode")
            .font(.system(size: 20, weight: .semibold))
            .foregroundColor(.white.opacity(0.7))
          Text("Voice conversation with AI. No video streaming.")
            .font(.system(size: 14))
            .foregroundColor(.white.opacity(0.5))
            .multilineTextAlignment(.center)
        }
      } else if let videoFrame = viewModel.currentVideoFrame, viewModel.hasReceivedFirstFrame {
        GeometryReader { geometry in
          Image(uiImage: videoFrame)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .edgesIgnoringSafeArea(.all)
      } else {
        VStack(spacing: 16) {
          SoundRings(isActive: true, symbol: "eyeglasses")
            .frame(width: 170, height: 170)
          Text("Waking up your glasses…")
            .font(ARTheme.display(17, weight: .medium))
            .foregroundColor(ARTheme.inkSoft)
        }
      }

      // Gemini status overlay (top) + speaking indicator
      if geminiVM.isGeminiActive {
        VStack {
          GeminiStatusBar(geminiVM: geminiVM)
          ListeningPill(geminiVM: geminiVM)
          if hasPackPlaceNearby, viewModel.currentVideoFrame != nil {
            Button {
              if let frame = viewModel.currentVideoFrame {
                referenceFrame = ReferenceFrame(image: frame)
              }
            } label: {
              Label("Reference photo", systemImage: "plus.viewfinder")
                .font(ARTheme.display(12, weight: .semibold))
                .foregroundColor(ARTheme.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(ARTheme.bubble)
                .cornerRadius(16)
                .arFloat()
            }
          }
          Spacer()

          VStack(spacing: 8) {
            if !geminiVM.userTranscript.isEmpty || !geminiVM.aiTranscript.isEmpty {
              TranscriptView(
                userText: geminiVM.userTranscript,
                aiText: geminiVM.aiTranscript
              )
            }

            ToolCallStatusView(status: geminiVM.toolCallStatus)

            if geminiVM.isModelSpeaking {
              HStack(spacing: 8) {
                Image(systemName: "speaker.wave.2.fill")
                  .foregroundColor(ARTheme.coral)
                  .font(.system(size: 14))
                SpeakingIndicator()
              }
              .padding(.horizontal, 16)
              .padding(.vertical, 8)
              .background(ARTheme.bubble)
              .cornerRadius(20)
              .arFloat()
            }
          }
          .padding(.bottom, 80)
        }
        .padding(.all, 24)
      }

      // WebRTC status overlay (top)
      if webrtcVM.isActive {
        VStack {
          WebRTCStatusBar(webrtcVM: webrtcVM)
          Spacer()
        }
        .padding(.all, 24)
      }

      // Bottom controls layer
      VStack {
        Spacer()
        ControlsView(viewModel: viewModel, geminiVM: geminiVM, webrtcVM: webrtcVM)
      }
      .padding(.all, 24)
    }
    .onDisappear {
      Task {
        if viewModel.streamingStatus != .stopped {
          await viewModel.stopSession()
        }
        if geminiVM.isGeminiActive {
          geminiVM.stopSession()
        }
        if webrtcVM.isActive {
          webrtcVM.stopSession()
        }
      }
    }
    // Show captured photos from DAT SDK in a preview sheet
    .sheet(isPresented: $viewModel.showPhotoPreview) {
      if let photo = viewModel.capturedPhoto {
        PhotoPreviewView(
          photo: photo,
          onDismiss: {
            viewModel.dismissPhotoPreview()
          }
        )
      }
    }
    // File the current glasses frame under a nearby pack place
    .sheet(item: $referenceFrame) { frame in
      AddReferencePhotoSheet(frame: frame)
    }
    // Gemini error alert
    .alert("Audio Guide", isPresented: Binding(
      get: { geminiVM.errorMessage != nil },
      set: { if !$0 { geminiVM.errorMessage = nil } }
    )) {
      Button("OK") { geminiVM.errorMessage = nil }
    } message: {
      Text(geminiVM.errorMessage ?? "")
    }
    // WebRTC error alert
    .alert("Live Stream", isPresented: Binding(
      get: { webrtcVM.errorMessage != nil },
      set: { if !$0 { webrtcVM.errorMessage = nil } }
    )) {
      Button("OK") { webrtcVM.errorMessage = nil }
    } message: {
      Text(webrtcVM.errorMessage ?? "")
    }
  }
}

// Extracted controls for clarity
struct ControlsView: View {
  @ObservedObject var viewModel: StreamSessionViewModel
  @ObservedObject var geminiVM: GeminiSessionViewModel
  @ObservedObject var webrtcVM: WebRTCSessionViewModel

  var body: some View {
    VStack(spacing: 8) {
      // Explain why AI and Live can't run at the same time
      if geminiVM.isGeminiActive {
        Text("Live streaming is unavailable while the guide is on.")
          .font(ARTheme.body(12))
          .foregroundColor(ARTheme.inkSoft)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 16)
          .padding(.vertical, 6)
          .background(ARTheme.bubble)
          .cornerRadius(10)
      } else if webrtcVM.isActive {
        Text("The guide is unavailable while live streaming is active.")
          .font(ARTheme.body(12))
          .foregroundColor(ARTheme.inkSoft)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 16)
          .padding(.vertical, 6)
          .background(ARTheme.bubble)
          .cornerRadius(10)
      }

      // Controls row
      HStack(spacing: 8) {
        CustomButton(
          title: "Stop",
          style: .destructive,
          isDisabled: false
        ) {
        Task {
          await viewModel.stopSession()
        }
      }

      // Photo button (glasses mode only -- DAT SDK capture)
      if viewModel.streamingMode == .glasses {
        CircleButton(icon: "camera.fill", text: nil) {
          viewModel.capturePhoto()
        }
      }

      // Flip camera button (iPhone camera mode only)
      if viewModel.streamingMode == .iPhone {
        VStack(spacing: 4) {
          CircleButton(icon: "camera.rotate.fill", text: nil) {
            viewModel.flipIPhoneCamera()
          }
          Text(viewModel.iPhoneCameraPosition == .front ? "Front" : "Back")
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.white)
        }
      }

      // Mic mute button for Gemini AI voice input (shown in all modes when AI is active:
      // glasses streaming, iPhone video, or audio-only)
      if geminiVM.isGeminiActive {
        CircleButton(
          icon: geminiVM.isMicMuted ? "mic.slash.fill" : "mic.fill",
          text: nil
        ) {
          geminiVM.toggleMicMute()
        }
      }

      // Gemini AI button (disabled when WebRTC is active — audio conflict)
      CircleButton(
        icon: geminiVM.isGeminiActive ? "waveform.circle.fill" : "waveform.circle",
        text: "Guide"
      ) {
        Task {
          if geminiVM.isGeminiActive {
            geminiVM.stopSession()
          } else {
            await geminiVM.startSession()
          }
        }
      }
      .opacity(webrtcVM.isActive ? 0.4 : 1.0)
      .disabled(webrtcVM.isActive)

      // WebRTC Live Stream button (disabled when Gemini is active — audio conflict)
      CircleButton(
        icon: webrtcVM.isActive
          ? "antenna.radiowaves.left.and.right.circle.fill"
          : "antenna.radiowaves.left.and.right.circle",
        text: "Live"
      ) {
        Task {
          if webrtcVM.isActive {
            webrtcVM.stopSession()
          } else {
            await webrtcVM.startSession()
          }
        }
      }
      .opacity(geminiVM.isGeminiActive ? 0.4 : 1.0)
      .disabled(geminiVM.isGeminiActive)
    }
    }
  }
}
