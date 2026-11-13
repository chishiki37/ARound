import AVFoundation
import UIKit

class IPhoneCameraManager: NSObject {
  private let captureSession = AVCaptureSession()
  private let videoOutput = AVCaptureVideoDataOutput()
  private let sessionQueue = DispatchQueue(label: "iphone-camera-session")
  private let context = CIContext()
  private var isRunning = false
  private(set) var currentPosition: AVCaptureDevice.Position = .back

  var onFrameCaptured: ((UIImage) -> Void)?

  func start() {
    guard !isRunning else { return }
    sessionQueue.async { [weak self] in
      self?.configureSession(position: .back)
      self?.captureSession.startRunning()
      self?.isRunning = true
    }
  }

  func stop() {
    guard isRunning else { return }
    sessionQueue.async { [weak self] in
      self?.captureSession.stopRunning()
      self?.isRunning = false
    }
  }

  @discardableResult
  func flipCamera() -> Bool {
    var success = false
    sessionQueue.sync { [weak self] in
      guard let self else { return }
      let newPosition: AVCaptureDevice.Position = self.currentPosition == .back ? .front : .back
      self.captureSession.beginConfiguration()
      self.removeCurrentVideoInput()
      success = self.addVideoInput(position: newPosition)
      if success {
        self.captureSession.commitConfiguration()
        self.currentPosition = newPosition
        NSLog("[iPhoneCamera] Flipped to \(newPosition == .front ? "front" : "back") camera")
      } else {
        // Revert to the previous camera so the session is not left without input
        let reverted = self.addVideoInput(position: self.currentPosition)
        self.captureSession.commitConfiguration()
        if !reverted {
          NSLog("[iPhoneCamera] Failed to add any camera input after flip attempt")
        }
      }
    }
    return success
  }

  private func configureSession(position: AVCaptureDevice.Position) {
    captureSession.beginConfiguration()
    captureSession.sessionPreset = .medium

    addVideoInput(position: position)

    // Add video output
    videoOutput.videoSettings = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ]
    videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
    videoOutput.alwaysDiscardsLateVideoFrames = true

    if captureSession.canAddOutput(videoOutput) {
      captureSession.addOutput(videoOutput)
    }

    // Force portrait-oriented frames from the sensor
    updateVideoConnectionRotation()

    captureSession.commitConfiguration()
    NSLog("[iPhoneCamera] Session configured with \(position == .front ? "front" : "back") camera")
  }

  @discardableResult
  private func addVideoInput(position: AVCaptureDevice.Position) -> Bool {
    guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
          let input = try? AVCaptureDeviceInput(device: camera) else {
      NSLog("[iPhoneCamera] Failed to access \(position == .front ? "front" : "back") camera")
      return false
    }

    if captureSession.canAddInput(input) {
      captureSession.addInput(input)
      return true
    }
    NSLog("[iPhoneCamera] Cannot add \(position == .front ? "front" : "back") camera input")
    return false
  }

  private func removeCurrentVideoInput() {
    for input in captureSession.inputs {
      if let deviceInput = input as? AVCaptureDeviceInput {
        captureSession.removeInput(deviceInput)
      }
    }
  }

  private func updateVideoConnectionRotation() {
    if let connection = videoOutput.connection(with: .video) {
      if connection.isVideoRotationAngleSupported(90) {
        connection.videoRotationAngle = 90
      }
    }
  }

  static func requestPermission() async -> Bool {
    let status = AVCaptureDevice.authorizationStatus(for: .video)
    switch status {
    case .authorized:
      return true
    case .notDetermined:
      return await AVCaptureDevice.requestAccess(for: .video)
    default:
      return false
    }
  }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension IPhoneCameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
  func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

    let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
    guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
    let image = UIImage(cgImage: cgImage)

    onFrameCaptured?(image)
  }
}
