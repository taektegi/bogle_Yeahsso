import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';

/// Why the camera can't be used.
enum CameraProblem {
  /// The child (or a parent) said no, or Screen Time restricts it.
  denied,

  /// This device has no camera to use (the simulator, for one).
  unavailable,

  /// It was there but failed to start.
  failed,
}

class CameraFailure implements Exception {
  const CameraFailure(this.problem);
  final CameraProblem problem;
  @override
  String toString() => 'CameraFailure($problem)';
}

/// The camera "Take a photo" looks through: the back camera, pointed at a
/// drawing on paper. An interface so tests and the simulator (which has no
/// camera) can stand in.
abstract interface class StudioCamera {
  /// Starts the camera; throws [CameraFailure].
  Future<void> open();

  /// The live picture, filling its box; valid once [open] succeeds.
  Widget preview();

  /// Width over height of the live picture as it is shown.
  double get aspectRatio;

  /// Whether a light can be turned on to see the paper better.
  bool get hasLight;
  Future<void> setLight(bool on);

  double get minZoom;
  double get maxZoom;
  Future<void> setZoom(double zoom);

  /// Focuses and meters on [point] (fractions of the preview).
  Future<void> focusAt(Offset point);

  /// Takes the picture: JPEG bytes, upright.
  Future<Uint8List> capture();

  Future<void> close();
}

/// Picks a photo already on the iPad; null when the child backs out.
typedef PhotoPicker = Future<Uint8List?> Function();

/// The iPad's own photo library (the system picker, which needs no
/// permission to browse).
Future<Uint8List?> pickFromLibrary() async {
  final file = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    maxWidth: 2400,
    maxHeight: 2400,
    imageQuality: 92,
  );
  return file?.readAsBytes();
}

/// The iPad's back camera.
class DeviceCamera implements StudioCamera {
  CameraController? _controller;
  bool _hasLight = false;
  double _minZoom = 1, _maxZoom = 1;

  CameraController get _camera => _controller!;

  @override
  Future<void> open() async {
    final List<CameraDescription> cameras;
    try {
      // A missing camera service may never answer; don't wait forever.
      cameras = await availableCameras().timeout(const Duration(seconds: 5));
    } on CameraException catch (e) {
      throw CameraFailure(_problem(e.code));
    } catch (_) {
      // No camera service here (tests, some simulators): nothing to open.
      throw const CameraFailure(CameraProblem.unavailable);
    }
    if (cameras.isEmpty) throw const CameraFailure(CameraProblem.unavailable);
    final back = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );
    final controller = CameraController(
      back,
      ResolutionPreset.veryHigh,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    try {
      await controller.initialize().timeout(const Duration(seconds: 10));
    } on CameraException catch (e) {
      await controller.dispose();
      throw CameraFailure(_problem(e.code));
    } on TimeoutException {
      await controller.dispose();
      throw const CameraFailure(CameraProblem.failed);
    }
    _controller = controller;
    try {
      await controller.setFlashMode(FlashMode.off);
      _hasLight = back.lensDirection == CameraLensDirection.back;
    } on CameraException {
      _hasLight = false;
    }
    try {
      _minZoom = await controller.getMinZoomLevel();
      _maxZoom = await controller.getMaxZoomLevel();
    } on CameraException {
      _minZoom = _maxZoom = 1;
    }
  }

  static CameraProblem _problem(String code) => switch (code) {
    'CameraAccessDenied' ||
    'CameraAccessDeniedWithoutPrompt' ||
    'CameraAccessRestricted' => CameraProblem.denied,
    'cameraNotFound' || 'noCamerasAvailable' => CameraProblem.unavailable,
    _ => CameraProblem.failed,
  };

  @override
  Widget preview() => CameraPreview(_camera);

  @override
  double get aspectRatio => _camera.value.aspectRatio;

  @override
  bool get hasLight => _hasLight;

  @override
  Future<void> setLight(bool on) async {
    try {
      await _camera.setFlashMode(on ? FlashMode.torch : FlashMode.off);
    } on CameraException {
      _hasLight = false;
    }
  }

  @override
  double get minZoom => _minZoom;

  @override
  // Beyond 5× a hand-held photo of paper is only blur.
  double get maxZoom => _maxZoom.clamp(_minZoom, 5.0);

  @override
  Future<void> setZoom(double zoom) async {
    try {
      await _camera.setZoomLevel(zoom.clamp(minZoom, maxZoom));
    } on CameraException {
      // Keeps the last zoom that worked.
    }
  }

  @override
  Future<void> focusAt(Offset point) async {
    try {
      await _camera.setFocusPoint(point);
      await _camera.setExposurePoint(point);
    } on CameraException {
      // Not every lens can focus on a point; it keeps auto focus.
    }
  }

  @override
  Future<Uint8List> capture() async {
    try {
      final file = await _camera.takePicture();
      return await file.readAsBytes();
    } catch (_) {
      throw const CameraFailure(CameraProblem.failed);
    }
  }

  @override
  Future<void> close() async {
    final controller = _controller;
    _controller = null;
    await controller?.dispose();
  }
}
