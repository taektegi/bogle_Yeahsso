import Flutter
import UIKit
import Vision
import CoreImage
import ImageIO

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BoglePhotoPreparation") {
      BoglePhotoPreparation.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BoglePencilInput") {
      BoglePencilInput.register(with: registrar)
    }
  }
}

/// UIKit hardware gestures remain native; drawing and tools stay in Flutter.
/// Kept in this compiled source so all Runner configurations register it.
final class BoglePencilInput: NSObject, FlutterPlugin, UIPencilInteractionDelegate {
  private let registrar: FlutterPluginRegistrar
  private let channel: FlutterMethodChannel
  private let interaction = UIPencilInteraction()
  private weak var attachedView: UIView?
  private var hover: UIHoverGestureRecognizer?

  init(registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
    channel = FlutterMethodChannel(name: "bogle/pencil", binaryMessenger: registrar.messenger())
    super.init()
    interaction.delegate = self
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = BoglePencilInput(registrar: registrar)
    registrar.addMethodCallDelegate(instance, channel: instance.channel)
    registrar.publish(instance)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "attach" else { result(FlutterMethodNotImplemented); return }
    guard let view = registrar.viewController?.view else {
      result(FlutterError(code: "no_view", message: "Flutter view is not attached", details: nil))
      return
    }
    if attachedView !== view {
      attachedView?.removeInteraction(interaction)
      if let hover { attachedView?.removeGestureRecognizer(hover) }
      view.addInteraction(interaction)
      let recognizer = UIHoverGestureRecognizer(target: self, action: #selector(hoverChanged(_:)))
      recognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
      recognizer.cancelsTouchesInView = false
      view.addGestureRecognizer(recognizer)
      hover = recognizer
      attachedView = view
    }
    result(["pencilOnly": UIPencilInteraction.prefersPencilOnlyDrawing])
  }

  private func doubleTap() {
    // App-specific pen/eraser toggle, disclosed in the pen settings. Respect
    // the user's system-wide choice to disable Pencil gestures entirely.
    guard UIPencilInteraction.preferredTapAction != .ignore else { return }
    channel.invokeMethod("doubleTap", arguments: nil)
  }

  func pencilInteractionDidTap(_ interaction: UIPencilInteraction) { doubleTap() }

  @available(iOS 17.5, *)
  func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
    doubleTap()
  }

  @available(iOS 17.5, *)
  func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
    guard squeeze.phase == .ended else { return }
    let action: String
    switch UIPencilInteraction.preferredSqueezeAction {
    case .switchEraser: action = "eraser"
    case .switchPrevious: action = "previous"
    case .showColorPalette: action = "colors"
    case .showInkAttributes: action = "width"
    case .showContextualPalette: action = "tools"
    default: return // Ignore/system shortcut stays under iPadOS control.
    }
    channel.invokeMethod("squeeze", arguments: ["action": action])
  }

  @objc private func hoverChanged(_ gesture: UIHoverGestureRecognizer) {
    if #available(iOS 17.5, *), !UIPencilInteraction.prefersHoverToolPreview { return }
    let visible = gesture.state == .began || gesture.state == .changed
    let point = gesture.location(in: attachedView)
    channel.invokeMethod("hover", arguments: ["visible": visible, "x": point.x, "y": point.y])
  }
}


/// On-device image preparation. Serial worker keeps Vision off the UI thread.
final class BoglePhotoPreparation: NSObject, FlutterPlugin {
  private let queue = DispatchQueue(label: "bogle.photo", qos: .userInitiated)
  private var working = false
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "bogle/photo", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(BoglePhotoPreparation(), channel: channel)
  }
  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "prepare" else { result(FlutterMethodNotImplemented); return }
    guard let args = call.arguments as? [String: Any],
          let typed = args["bytes"] as? FlutterStandardTypedData,
          typed.data.count <= 40 * 1024 * 1024 else {
      result(FlutterError(code: "invalid_photo", message: "사진을 다시 골라 주세요.", details: nil)); return
    }
    guard !working else {
      result(FlutterError(code: "preparation_busy", message: "사진 정리가 아직 진행 중이에요. 잠시 기다리거나 원본으로 진행해 주세요.", details: nil)); return
    }
    working = true
    queue.async {
      autoreleasepool {
        do {
          let bytes = try self.prepare(typed.data, args: args)
          DispatchQueue.main.async { self.working = false; result(FlutterStandardTypedData(bytes: bytes)) }
        } catch {
          DispatchQueue.main.async {
            self.working = false
            result(FlutterError(code: "preparation_unavailable", message: "대상을 찾지 못했어요. 대상의 가운데를 누르거나 직접 잘라 주세요. 원본은 그대로 있어요.", details: (error as? PhotoError)?.rawValue ?? "\((error as NSError).domain):\((error as NSError).code)"))
          }
        }
      }
    }
  }
  private func prepare(_ data: Data, args: [String: Any]) throws -> Data {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let raw = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw PhotoError.invalid }
    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    let orientation = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.int32Value ?? 1
    let context = CIContext(options: [.cacheIntermediates: false])
    let upright = CIImage(cgImage: raw).oriented(forExifOrientation: orientation)
    guard let cg = context.createCGImage(upright, from: upright.extent),
          cg.width <= 4096, cg.height <= 4096 else { throw PhotoError.invalid }
    let image = CIImage(cgImage: cg)
    // Vision analyzes a real RGB photograph, even when the supplied preview
    // already has transparent margins. Keep its original coordinate system.
    let matte = CIImage(color: CIColor.white).cropped(to: image.extent)
    guard let visionImage = context.createCGImage(image.composited(over: matte), from: image.extent) else { throw PhotoError.invalid }
    let handler = VNImageRequestHandler(cgImage: visionImage, options: [:])
    let prepared: CIImage
    if args["paper"] as? Bool == true {
      let request = VNDetectRectanglesRequest()
      request.maximumObservations = 1
      request.minimumConfidence = 0.7
      request.minimumAspectRatio = 0.25
      request.minimumSize = 0.3
      try handler.perform([request])
      guard let rect = request.results?.first else { throw PhotoError.noPaper }
      func vector(_ p: CGPoint) -> CIVector {
        CIVector(x: p.x * image.extent.width, y: p.y * image.extent.height)
      }
      prepared = image.applyingFilter("CIPerspectiveCorrection", parameters: [
        "inputTopLeft": vector(rect.topLeft), "inputTopRight": vector(rect.topRight),
        "inputBottomLeft": vector(rect.bottomLeft), "inputBottomRight": vector(rect.bottomRight),
      ])
    } else {
      guard #available(iOS 17.0, *) else { throw PhotoError.invalid }
      let request = VNGenerateForegroundInstanceMaskRequest()
      try handler.perform([request])
      guard let observation = request.results?.first else { throw PhotoError.noSubject }
      let mask = observation.instanceMask
      guard CVPixelBufferGetPixelFormatType(mask) == kCVPixelFormatType_OneComponent8 else { throw PhotoError.unsupportedMask }
      CVPixelBufferLockBaseAddress(mask, .readOnly)
      let width = CVPixelBufferGetWidth(mask), height = CVPixelBufferGetHeight(mask)
      let x = min(width - 1, max(0, Int((args["x"] as? Double ?? 0.5) * Double(width))))
      let y = min(height - 1, max(0, Int((args["y"] as? Double ?? 0.5) * Double(height))))
      let row = CVPixelBufferGetBytesPerRow(mask)
      guard let address = CVPixelBufferGetBaseAddress(mask) else {
        CVPixelBufferUnlockBaseAddress(mask, .readOnly); throw PhotoError.invalid
      }
      let instance = Int(address.assumingMemoryBound(to: UInt8.self)[y * row + x])
      CVPixelBufferUnlockBaseAddress(mask, .readOnly)
      guard instance > 0, observation.allInstances.contains(instance) else { throw PhotoError.backgroundPoint }
      let cutout = try observation.generateMaskedImage(ofInstances: IndexSet(integer: instance), from: handler, croppedToInstancesExtent: true)
      prepared = CIImage(cvPixelBuffer: cutout)
    }
    // Keep a safe transparent margin around cutouts; paper keeps its full colour.
    let extent = prepared.extent
    guard extent.width >= 64, extent.height >= 64 else { throw PhotoError.invalid }
    let scale = min(1, 1800 / max(extent.width, extent.height))
    let normalized = prepared.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
      .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    let margin: CGFloat = args["paper"] as? Bool == true ? 0 : 60
    let shifted = normalized.transformed(by: CGAffineTransform(translationX: margin, y: margin))
    let outputRect = CGRect(x: 0, y: 0, width: ceil(extent.width * scale + margin * 2), height: ceil(extent.height * scale + margin * 2))
    guard let output = context.createCGImage(shifted, from: outputRect),
          let png = UIImage(cgImage: output).pngData() else { throw PhotoError.invalid }
    return png
  }
  private enum PhotoError: String, Error { case invalid, noPaper, noSubject, unsupportedMask, backgroundPoint }
}
