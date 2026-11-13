/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// NonStreamView.swift
//
// Default screen to show getting started tips after app connection
// Initiates streaming
//

import MWDATCamera
import MWDATCore
import SwiftUI

struct NonStreamView: View {
  @ObservedObject var viewModel: StreamSessionViewModel
  @ObservedObject var wearablesVM: WearablesViewModel
  @State private var sheetHeight: CGFloat = 300
  @State private var showSettings = false
  @State private var settingsRefreshToken = UUID()

  private var isRegistered: Bool {
    wearablesVM.registrationState == .registered
  }

  var body: some View {
    ZStack {
      ARBackground()

      VStack {
        HStack {
          ARoundWordmark(size: 26)
          Spacer()
          Menu {
            Button("Settings") {
              showSettings = true
            }
            Button("Disconnect", role: .destructive) {
              wearablesVM.disconnectGlasses()
            }
            .disabled(!isRegistered)
          } label: {
            Image(systemName: "gearshape")
              .resizable()
              .aspectRatio(contentMode: .fit)
              .foregroundColor(ARTheme.ink)
              .frame(width: 24, height: 24)
          }
        }

        Spacer()

        VStack(spacing: 14) {
          SoundRings(isActive: isRegistered && viewModel.hasActiveDevice)
            .frame(width: 190, height: 190)

          Text(isRegistered ? "Look around.\nHear the story." : "Let's get you set up")
            .font(ARTheme.display(28, weight: .heavy))
            .foregroundColor(ARTheme.ink)
            .multilineTextAlignment(.center)

          Text(isRegistered
            ? "Pop your glasses on and just ask: \"What am I looking at?\" Your guide sees what you see, knows where you are, and answers in your ear."
            : "Connect your Meta Ray-Ban glasses and your guide is ready to wander with you.")
            .font(ARTheme.body(15))
            .multilineTextAlignment(.center)
            .foregroundColor(ARTheme.inkSoft)
            .fixedSize(horizontal: false, vertical: true)

          ConfigurationSummaryCard()
            .id(settingsRefreshToken)
            .padding(.top, 6)
        }
        .padding(.horizontal, 12)

        Spacer()

        // Empty state when no glasses are connected
        if !viewModel.hasActiveDevice {
          HStack(spacing: 12) {
            Image(systemName: "eyeglasses")
              .font(.system(size: 22, weight: .medium))
              .foregroundColor(ARTheme.grape)

            VStack(alignment: .leading, spacing: 2) {
              Text("No glasses yet")
                .font(ARTheme.display(15, weight: .semibold))
                .foregroundColor(ARTheme.ink)

              Text("Pop them on and check they are paired and switched on.")
                .font(ARTheme.body(13))
                .foregroundColor(ARTheme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 14)
          .arCard()
          .padding(.bottom, 12)
        }

        // Resolution picker (glasses mode only)
        VStack(spacing: 4) {
          Text("Camera detail")
            .font(ARTheme.body(13))
            .foregroundColor(ARTheme.inkSoft)
          Picker("Resolution", selection: Binding(
            get: { viewModel.selectedResolution },
            set: { viewModel.updateResolution($0) }
          )) {
            Text("Low").tag(StreamingResolution.low)
            Text("Med").tag(StreamingResolution.medium)
            Text("High").tag(StreamingResolution.high)
          }
          .pickerStyle(.segmented)
          Text(viewModel.resolutionLabel)
            .font(.system(size: 12, design: .monospaced))
            .foregroundColor(ARTheme.inkFaint)
        }
        .padding(.bottom, 12)

        if wearablesVM.registrationState == .registered {
          CustomButton(
            title: "Let's explore",
            style: .primary,
            isDisabled: !viewModel.hasActiveDevice
          ) {
            Task {
              await viewModel.handleStartStreaming()
            }
          }
        } else {
          CustomButton(
            title: "Connect my Glasses",
            style: .primary,
            isDisabled: false
          ) {
            wearablesVM.connectGlasses()
          }
        }
      }
      .padding(.all, 24)
    }
    .sheet(isPresented: $showSettings, onDismiss: {
      settingsRefreshToken = UUID()
    }) {
      SettingsView(wearablesViewModel: wearablesVM)
    }
    .sheet(isPresented: $wearablesVM.showGettingStartedSheet) {
      if #available(iOS 16.0, *) {
        GettingStartedSheetView(height: $sheetHeight)
          .presentationDetents([.height(sheetHeight)])
          .presentationDragIndicator(.visible)
      } else {
        GettingStartedSheetView(height: $sheetHeight)
      }
    }
  }
}

struct GettingStartedSheetView: View {
  @Environment(\.dismiss) var dismiss
  @Binding var height: CGFloat

  var body: some View {
    VStack(spacing: 24) {
      Text("Getting started")
        .font(.system(size: 18, weight: .semibold))
        .foregroundColor(.primary)

      VStack(spacing: 12) {
        TipItemView(
          resource: .videoIcon,
          text: "First, ARound needs permission to use your glasses camera."
        )
        TipItemView(
          resource: .tapIcon,
          text: "Capture photos by tapping the camera button."
        )
        TipItemView(
          resource: .smartGlassesIcon,
          text: "The capture LED lets others know when you're capturing content or going live."
        )
      }
      .padding(.bottom, 16)

      CustomButton(
        title: "Continue",
        style: .primary,
        isDisabled: false
      ) {
        dismiss()
      }
    }
    .padding(.all, 24)
    .background(
      GeometryReader { geo -> Color in
        DispatchQueue.main.async {
          height = geo.size.height
        }
        return Color.clear
      }
    )
  }
}

struct TipItemView: View {
  let resource: ImageResource
  let text: String

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(resource)
        .resizable()
        .renderingMode(.template)
        .foregroundColor(.primary)
        .aspectRatio(contentMode: .fit)
        .frame(width: 24)
        .padding(.leading, 4)
        .padding(.top, 4)

      Text(text)
        .font(.system(size: 15))
        .foregroundColor(.primary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
