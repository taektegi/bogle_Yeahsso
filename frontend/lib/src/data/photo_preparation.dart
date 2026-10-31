import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/services.dart';

/// Device-only preparation. No AI credentials or network requests are involved.
abstract final class PhotoPreparation {
  static const channel = MethodChannel('bogle/photo');

  static Future<Uint8List> prepare(
    Uint8List bytes, {
    required bool paper,
    required ui.Offset subject,
  }) async {
    final result = await channel
        .invokeMethod<Uint8List>('prepare', {
          'bytes': bytes,
          'paper': paper,
          'x': subject.dx,
          'y': subject.dy,
        })
        .timeout(const Duration(seconds: 25));
    if (result == null || result.isEmpty) {
      throw const FormatException('사진을 정리하지 못했어요.');
    }
    return result;
  }

  /// Gentle capture guidance, never an automatic rejection of pale artwork.
  static Future<String?> assess(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 64,
        targetHeight: 64,
      );
      ui.Image? image;
      try {
        image = (await codec.getNextFrame()).image;
        final pixels = await image.toByteData();
        if (pixels == null) return null;
        final luminance = <double>[];
        for (var i = 0; i < pixels.lengthInBytes; i += 4) {
          final alpha = pixels.getUint8(i + 3) / 255;
          luminance.add(
            (.2126 * pixels.getUint8(i) +
                        .7152 * pixels.getUint8(i + 1) +
                        .0722 * pixels.getUint8(i + 2)) *
                    alpha +
                255 * (1 - alpha),
          );
        }
        final mean = luminance.reduce((a, b) => a + b) / luminance.length;
        final variance =
            luminance
                .map((v) => (v - mean) * (v - mean))
                .reduce((a, b) => a + b) /
            luminance.length;
        var edges = 0.0;
        for (var y = 1; y < image.height; y++) {
          for (var x = 1; x < image.width; x++) {
            final at = y * image.width + x;
            edges +=
                (luminance[at] - luminance[at - 1]).abs() +
                (luminance[at] - luminance[at - image.width]).abs();
          }
        }
        if (mean < 35) return '사진이 어두워요. 밝은 곳에서 다시 찍으면 더 잘 알아볼 수 있어요.';
        if (variance < 25) return '대상이 잘 보이지 않을 수 있어요. 가까이 찍거나 사진을 잘라 주세요.';
        if (edges / (2 * luminance.length) < 1.4) {
          return '사진이 흐릴 수 있어요. 초점을 맞춰 다시 찍으면 더 좋아요.';
        }
        return null;
      } finally {
        image?.dispose();
        codec.dispose();
      }
    } catch (_) {
      return '사진을 읽기 어려워요. 다른 사진을 골라 주세요.';
    }
  }

  /// Decode at a bounded size and encode a real PNG, including HEIF inputs
  /// supported by the device. Never stretch a narrow image to meet the limit.
  static Future<Uint8List> normalize(Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > 40 * 1024 * 1024) {
      throw const FormatException('40MB 이하의 사진을 골라 주세요.');
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    ui.ImageDescriptor? descriptor;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final width = descriptor.width, height = descriptor.height;
      if (math.min(width, height) < 64 ||
          math.max(width, height) / math.min(width, height) > 24) {
        throw const FormatException('사진이 너무 작거나 가늘어요. 넓게 다시 골라 주세요.');
      }
      final scale = math.min(1.0, 2048 / math.max(width, height));
      final codec = await descriptor.instantiateCodec(
        targetWidth: (width * scale).round(),
        targetHeight: (height * scale).round(),
      );
      ui.Image? image;
      try {
        image = (await codec.getNextFrame()).image;
        if (math.min(image.width, image.height) < 64) {
          throw const FormatException('사진을 조금 더 넓게 골라 주세요.');
        }
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        if (png == null) throw const FormatException('사진을 읽지 못했어요.');
        return png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes);
      } finally {
        image?.dispose();
        codec.dispose();
      }
    } finally {
      descriptor?.dispose();
      buffer.dispose();
    }
  }
}
