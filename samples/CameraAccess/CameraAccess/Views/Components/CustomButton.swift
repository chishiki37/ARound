/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// CustomButton.swift
//
// Reusable button component used throughout the CameraAccess app for consistent styling.
//

import SwiftUI

struct CustomButton: View {
  let title: String
  let style: ButtonStyle
  let isDisabled: Bool
  let action: () -> Void

  enum ButtonStyle {
    case primary, secondary, destructive

    var backgroundColor: Color {
      switch self {
      case .primary:
        return ARTheme.coral
      case .secondary, .destructive:
        return Color.white
      }
    }

    var foregroundColor: Color {
      switch self {
      case .primary:
        return Color.white
      case .secondary:
        return ARTheme.ink
      case .destructive:
        return ARTheme.coral
      }
    }
  }

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(ARTheme.display(18, weight: .heavy))
        .foregroundColor(style.foregroundColor)
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .background(style.backgroundColor)
        .cornerRadius(28)
        .arFloat()
    }
    .disabled(isDisabled)
    .opacity(isDisabled ? 0.45 : 1.0)
  }
}
