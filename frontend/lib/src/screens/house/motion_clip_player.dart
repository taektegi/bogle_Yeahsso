import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../data/art_source.dart';

/// A motion clip (an animated GIF from the motion service) read once and
/// measured, ready to play.
///
/// The house plays clips itself rather than through [Image]: an animated
/// [Image] carries on from whatever frame it was left on, so a second wave
/// would start halfway, and it loops, so a clip cut at a fixed time either
/// stops mid-move or starts over. Played from these bytes, every play starts
/// at the first frame and ends with the last.
class LoadedClip {
  const LoadedClip({
    required this.bytes,
    required this.size,
    required this.length,
    required this.figure,
  });

  final Uint8List bytes;

  /// The clip's size in pixels.
  final Size size;

  /// One play, first frame to last.
  final Duration length;

  /// Where the friend is drawn in the first frame, in pixels: the house
  /// stands it exactly where its drawing stands, at the drawing's height.
  final Rect figure;

  /// Clips longer than this are cut short; shorter ones aren't worth it.
  static const longest = Duration(seconds: 6);
  static const shortest = Duration(milliseconds: 300);

  /// Reads and measures the clip at [path] (a file, asset or URL); null if
  /// it can't be read, has a single frame or shows nothing to line up.
  static Future<LoadedClip?> load(String path) async {
    ui.Codec? codec;
    try {
      final bytes = await loadArtBytes(path);
      codec = await ui.instantiateImageCodec(bytes);
      if (codec.frameCount < 2) return null;
      var length = Duration.zero;
      Size? size;
      Rect? figure;
      for (var i = 0; i < codec.frameCount; i++) {
        final frame = await codec.getNextFrame();
        length += frameTime(frame.duration);
        if (i == 0) {
          final image = frame.image;
          size = Size(image.width.toDouble(), image.height.toDouble());
          figure = await _drawn(image);
        }
        frame.image.dispose();
      }
      if (figure == null || length < shortest) return null;
      return LoadedClip(
        bytes: bytes,
        size: size!,
        length: length > longest ? longest : length,
        figure: figure,
      );
    } catch (_) {
      return null;
    } finally {
      codec?.dispose();
    }
  }

  /// How long a frame shows: GIFs often say 0 or 10 ms, which every
  /// player treats as "as fast as normal", about 100 ms.
  static Duration frameTime(Duration said) =>
      said < const Duration(milliseconds: 20)
      ? const Duration(milliseconds: 100)
      : said;

  /// The part of [image] that isn't clear, or null when all of it is.
  static Future<Rect?> _drawn(ui.Image image) async {
    final data = await image.toByteData();
    if (data == null) return null;
    final w = image.width, h = image.height;
    var left = w, top = h, right = -1, bottom = -1;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (data.getUint8((y * w + x) * 4 + 3) > 24) {
          if (x < left) left = x;
          if (x > right) right = x;
          if (y < top) top = y;
          if (y > bottom) bottom = y;
        }
      }
    }
    if (right < 0) return null;
    return Rect.fromLTRB(
      left.toDouble(),
      top.toDouble(),
      right + 1.0,
      bottom + 1.0,
    );
  }
}

/// Plays a [LoadedClip] once, from its first frame to its last, filling
/// the space it is given. [onStarted] comes with the first frame (until
/// then nothing shows, so the drawing can stay until there is something to
/// take its place) and [onDone] after the last, or as soon as it can't be
/// played.
class MotionClipPlayer extends StatefulWidget {
  const MotionClipPlayer({
    super.key,
    required this.clip,
    required this.onStarted,
    required this.onDone,
    this.semanticLabel,
  });

  final LoadedClip clip;
  final VoidCallback onStarted;
  final VoidCallback onDone;
  final String? semanticLabel;

  @override
  State<MotionClipPlayer> createState() => _MotionClipPlayerState();
}

class _MotionClipPlayerState extends State<MotionClipPlayer> {
  ui.Codec? _codec;
  ui.Image? _frame;
  Timer? _next;
  bool _gone = false;
  int _shown = 0;
  Duration _played = Duration.zero;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final codec = await ui.instantiateImageCodec(widget.clip.bytes);
      if (_gone) {
        codec.dispose();
        return;
      }
      _codec = codec;
      await _show();
    } catch (_) {
      _finish();
    }
  }

  Future<void> _show() async {
    final codec = _codec;
    if (_gone || codec == null) return;
    if (_shown >= codec.frameCount || _played >= widget.clip.length) {
      _finish();
      return;
    }
    final ui.FrameInfo frame;
    try {
      frame = await codec.getNextFrame();
    } catch (_) {
      _finish();
      return;
    }
    if (_gone) {
      frame.image.dispose();
      return;
    }
    final first = _shown == 0;
    setState(() {
      _frame?.dispose();
      _frame = frame.image;
    });
    _shown++;
    final time = LoadedClip.frameTime(frame.duration);
    _played += time;
    if (first) widget.onStarted();
    _next = Timer(time, _show);
  }

  void _finish() {
    if (_gone) return;
    _gone = true;
    widget.onDone();
  }

  @override
  void dispose() {
    _gone = true;
    _next?.cancel();
    _frame?.dispose();
    _codec?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: widget.semanticLabel,
    child: RawImage(image: _frame, fit: BoxFit.fill),
  );
}
