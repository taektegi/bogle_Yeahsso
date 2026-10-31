import 'dart:async';

import 'package:flutter/services.dart';

/// One channel handler per engine, multiple screen subscribers. Hidden routes
/// filter events themselves, so revisiting a studio does not steal callbacks.
abstract final class PencilInput {
  static const channel = MethodChannel('bogle/pencil');
  static final _events = StreamController<MethodCall>.broadcast(sync: true);
  static bool _initialized = false;

  static Stream<MethodCall> get events {
    if (!_initialized) {
      _initialized = true;
      channel.setMethodCallHandler((call) async => _events.add(call));
    }
    return _events.stream;
  }

  static Future<bool?> attach() async {
    try {
      final result = await channel.invokeMapMethod<String, Object?>('attach');
      return result?['pencilOnly'] as bool?;
    } on MissingPluginException {
      return null; // Non-iOS builds and widget tests retain touch drawing.
    } on PlatformException {
      return null; // No foreground Flutter view yet; retry on resume.
    }
  }
}
