/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// PhotoPreviewView.swift
//
// UI for previewing and sharing photos captured from Meta wearable devices via the DAT SDK.
// This view displays photos captured using StreamSession.capturePhoto() and provides explicit
// Share, Save, and Cancel actions so the user can review before doing anything.
//

import SwiftUI

struct PhotoPreviewView: View {
  let photo: UIImage
  let onDismiss: () -> Void

  @State private var showShareSheet = false
  @State private var showSaveConfirmation = false
  @State private var dragOffset = CGSize.zero

  var body: some View {
    ZStack {
      // Semi-transparent background overlay
      Color.black.opacity(0.8)
        .ignoresSafeArea()
        .onTapGesture {
          dismissWithAnimation()
        }

      VStack(spacing: 20) {
        photoDisplayView

        // Explicit review actions
        HStack(spacing: 16) {
          actionButton(
            title: "Cancel",
            systemImage: "xmark",
            role: .cancel
          ) {
            dismissWithAnimation()
          }

          actionButton(
            title: "Save",
            systemImage: "square.and.arrow.down",
            role: nil
          ) {
            savePhoto()
          }

          actionButton(
            title: "Share",
            systemImage: "square.and.arrow.up",
            role: nil
          ) {
            showShareSheet = true
          }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
      }
      .padding()
      .offset(dragOffset)
      .animation(.spring(response: 0.6, dampingFraction: 0.8), value: dragOffset)
    }
    .sheet(
      isPresented: $showShareSheet,
      onDismiss: {
        // Keep the preview open after sharing so the user can also save or cancel
      }
    ) {
      ShareSheet(photo: photo)
    }
    .alert("Saved to Photos", isPresented: $showSaveConfirmation) {
      Button("OK", role: .cancel) {}
    } message: {
      Text("The photo has been saved to your camera roll.")
    }
  }

  private func actionButton(
    title: String,
    systemImage: String,
    role: ButtonRole?,
    action: @escaping () -> Void
  ) -> some View {
    Button(role: role) {
      action()
    } label: {
      VStack(spacing: 6) {
        Image(systemName: systemImage)
          .font(.system(size: 22, weight: .semibold))
        Text(title)
          .font(.system(size: 13, weight: .medium))
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 12)
      .background(role == .cancel ? Color.white.opacity(0.15) : Color.white)
      .foregroundColor(role == .cancel ? .white : .black)
      .cornerRadius(12)
    }
  }

  private var photoDisplayView: some View {
    GeometryReader { geometry in
      Image(uiImage: photo)
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height * 0.7)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
        .gesture(
          DragGesture()
            .onChanged { value in
              dragOffset = value.translation
            }
            .onEnded { value in
              if abs(value.translation.height) > 100 {
                dismissWithAnimation()
              } else {
                withAnimation(.spring()) {
                  dragOffset = .zero
                }
              }
            }
        )
    }
  }

  private func savePhoto() {
    UIImageWriteToSavedPhotosAlbum(photo, nil, nil, nil)
    showSaveConfirmation = true
  }

  private func dismissWithAnimation() {
    withAnimation(.easeInOut(duration: 0.3)) {
      dragOffset = CGSize(width: 0, height: UIScreen.main.bounds.height)
    }
    Task {
      try? await Task.sleep(nanoseconds: 300_000_000)
      onDismiss()
    }
  }
}

struct ShareSheet: UIViewControllerRepresentable {
  let photo: UIImage

  func makeUIViewController(context: Context) -> UIActivityViewController {
    let activityViewController = UIActivityViewController(
      activityItems: [photo],
      applicationActivities: nil
    )

    // Exclude certain activity types if needed
    activityViewController.excludedActivityTypes = [
      .assignToContact,
      .addToReadingList,
    ]

    return activityViewController
  }

  func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
    // No updates needed
  }
}
