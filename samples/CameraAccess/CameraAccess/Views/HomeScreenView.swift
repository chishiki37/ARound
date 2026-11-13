/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// HomeScreenView.swift
//
// Welcome screen that guides users through the DAT SDK registration process.
// This view is displayed when the app is not yet registered.
//

import MWDATCore
import SwiftUI

struct HomeScreenView: View {
  @ObservedObject var viewModel: WearablesViewModel
  @State private var showSettings = false

  var body: some View {
    ZStack {
      Color.white.edgesIgnoringSafeArea(.all)

      VStack(spacing: 12) {
        HStack {
          Spacer()
          Button {
            showSettings = true
          } label: {
            Image(systemName: "gearshape")
              .resizable()
              .aspectRatio(contentMode: .fit)
              .foregroundColor(.black)
              .frame(width: 24, height: 24)
          }
        }

        // Current AI / Agent configuration summary
        ConfigurationSummaryCard()

        Spacer()

        Image(.cameraAccessIcon)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(width: 120)

        VStack(spacing: 12) {
          HomeTipItemView(
            resource: .smartGlassesIcon,
            title: "Sees What You See",
            text: "Your guide looks through your glasses camera to recognise what is in front of you."
          )
          HomeTipItemView(
            resource: .soundIcon,
            title: "Ask Out Loud",
            text: "Ask \"What am I looking at?\" and hear the answer through your glasses."
          )
          HomeTipItemView(
            resource: .walkingIcon,
            title: "Knows Where You Are",
            text: "Your phone's location helps the guide tell nearby places apart."
          )
        }

        Spacer()

        VStack(spacing: 20) {
          Text("You'll be redirected to the Meta AI app to confirm your connection.")
            .font(.system(size: 14))
            .foregroundColor(.gray)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)

          CustomButton(
            title: viewModel.registrationState == .registering ? "Connecting..." : "Connect my glasses",
            style: .primary,
            isDisabled: viewModel.registrationState == .registering
          ) {
            viewModel.connectGlasses()
          }

        }
      }
      .padding(.all, 24)
    }
    .sheet(isPresented: $showSettings) {
      SettingsView(wearablesViewModel: viewModel)
    }
  }

}

internal struct ConfigurationSummaryCard: View {
  private let settings = SettingsManager.shared

  private var modelLabel: String {
    settings.selectedModel == "openai" ? "OpenAI" : "Gemini"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text("Guide voice")
          .font(.system(size: 13, weight: .medium))
          .foregroundColor(ARTheme.inkSoft)
        Spacer()
        Text(modelLabel)
          .font(.system(size: 13, weight: .semibold))
          .foregroundColor(ARTheme.ink)
      }

      HStack {
        Text("Location")
          .font(.system(size: 13, weight: .medium))
          .foregroundColor(ARTheme.inkSoft)
        Spacer()
        Text(settings.locationSharingEnabled ? "Shared with guide" : "Off")
          .font(.system(size: 13, weight: .semibold))
          .foregroundColor(ARTheme.ink)
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .arCard()
  }
}

struct HomeTipItemView: View {
  let resource: ImageResource
  let title: String
  let text: String

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(resource)
        .resizable()
        .renderingMode(.template)
        .foregroundColor(.black)
        .aspectRatio(contentMode: .fit)
        .frame(width: 24)
        .padding(.leading, 4)
        .padding(.top, 4)

      VStack(alignment: .leading, spacing: 6) {
        Text(title)
          .font(.system(size: 18, weight: .semibold))
          .foregroundColor(.black)

        Text(text)
          .font(.system(size: 15))
          .foregroundColor(.gray)
      }
      Spacer()
    }
  }
}
