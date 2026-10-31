import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'shape_recognizer.dart';

enum DrawingTool { pen, marker, eraser }

/// Goodnotes-style erasers: rub out just the ink under the eraser, or lift
/// whole strokes it touches.
enum EraserMode { partial, stroke }

class DrawingStroke {
  DrawingStroke(this.start, this.color, this.width, this.erase)
    : path = (Path()..moveTo(start.dx, start.dy)),
      points = [start];
  final Offset start;
  final Color color;
  final double width;
  final bool erase;
  final Path path;

  /// The same line as [path], kept for hit-testing by the stroke eraser.
  final List<Offset> points;
  bool isDot = true;
  RecognizedShape? shape;
  bool filled = false;
  bool smoothed = false;

  /// Whether a round eraser of [radius] at [p] touches the drawn line.
  bool touches(Offset p, double radius) {
    if (filled && path.contains(p)) return true;
    final reach = radius + width / 2;
    if (points.length == 1) return (points.first - p).distance <= reach;
    for (var i = 1; i < points.length; i++) {
      if (_distanceToSegment(p, points[i - 1], points[i]) <= reach) {
        return true;
      }
    }
    return false;
  }

  static double _distanceToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final length = ab.distanceSquared;
    if (length == 0) return (p - a).distance;
    final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / length).clamp(
      0.0,
      1.0,
    );
    return (p - (a + ab * t)).distance;
  }

  void paint(Canvas canvas) {
    final paint = Paint()
      ..color = color
      ..blendMode = erase ? BlendMode.clear : BlendMode.srcOver
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (isDot) {
      canvas.drawCircle(start, width / 2, paint);
    } else {
      if (filled) canvas.drawPath(path, paint);
      canvas.drawPath(path, paint..style = PaintingStyle.stroke);
    }
  }
}

/// Pointer updates repaint only the ink layer. History controls update on commit.
class DrawingController extends ChangeNotifier {
  final ValueNotifier<int> history = ValueNotifier(0);
  final List<DrawingStroke> _strokes = [];
  final List<List<DrawingStroke>> _undo = [];
  final List<List<DrawingStroke>> _redo = [];
  DrawingStroke? _active;
  DrawingStroke? _corrected;
  Timer? _holdTimer;
  Offset? _holdAnchor;
  double _inputScale = 1;
  bool drawAndHold = true;
  bool snapToShapes = true;
  bool fillShapes = false;
  bool stabilize = true;

  /// Old drafts had no paper metadata. Include undo/redo ink when migrating,
  /// so opening them on a smaller screen never clips recoverable strokes.
  Size paperExtent(Size fallback) {
    var width = fallback.width, height = fallback.height;
    for (final stroke in [
      ..._strokes,
      ..._undo.expand((h) => h),
      ..._redo.expand((h) => h),
    ]) {
      for (final point in stroke.points) {
        width = math.max(width, point.dx + stroke.width / 2);
        height = math.max(height, point.dy + stroke.width / 2);
      }
    }
    return Size(width, height);
  }

  Map<String, Object?> snapshot() {
    Map<String, Object?> stroke(DrawingStroke s) => {
      'points': [
        for (final p in s.points) [p.dx, p.dy],
      ],
      'color': s.color.toARGB32(),
      'width': s.width,
      'erase': s.erase,
      'filled': s.filled,
      'shape': s.shape?.kind.name,
      'smoothed': s.smoothed,
    };
    return {
      'strokes': _strokes.map(stroke).toList(),
      'undo': _undo
          .skip(math.max(0, _undo.length - 80))
          .map((h) => h.map(stroke).toList())
          .toList(),
      'redo': _redo.map((h) => h.map(stroke).toList()).toList(),
      'hold': drawAndHold,
      'snap': snapToShapes,
      'fill': fillShapes,
      'stabilize': stabilize,
    };
  }

  void restore(Map data) {
    List<DrawingStroke> read(Object? source) => [
      for (final raw in source as List? ?? [])
        if (raw is Map &&
            raw['points'] is List &&
            (raw['points'] as List).isNotEmpty)
          _restoredStroke(raw),
    ];
    final strokes = read(data['strokes']);
    final undo = [for (final h in data['undo'] as List? ?? []) read(h)];
    final redo = [for (final h in data['redo'] as List? ?? []) read(h)];
    _strokes
      ..clear()
      ..addAll(strokes);
    _undo
      ..clear()
      ..addAll(undo);
    _redo
      ..clear()
      ..addAll(redo);
    drawAndHold = data['hold'] != false;
    snapToShapes = data['snap'] != false;
    fillShapes = data['fill'] == true;
    stabilize = data['stabilize'] != false;
    _changed();
  }

  static DrawingStroke _restoredStroke(Map raw) {
    final points = [
      for (final p in raw['points'] as List)
        Offset((p[0] as num).toDouble(), (p[1] as num).toDouble()),
    ];
    if (points.any((p) => !p.dx.isFinite || !p.dy.isFinite)) {
      throw const FormatException('Invalid stroke');
    }
    final stroke =
        DrawingStroke(
            points.first,
            Color(raw['color'] as int),
            (raw['width'] as num).toDouble().clamp(1, 128),
            raw['erase'] == true,
          )
          ..points.clear()
          ..points.addAll(points)
          ..isDot = points.length == 1
          ..filled = raw['filled'] == true;
    stroke.smoothed = raw['smoothed'] == true;
    final shape = SketchShape.values.asNameMap()[raw['shape']];
    if (shape != null) {
      stroke.shape = RecognizedShape(shape, points);
      stroke.path
        ..reset()
        ..addPath(stroke.shape!.path, Offset.zero);
    } else {
      for (var i = 1; i < points.length; i++) {
        final p = points[i], previous = points[i - 1];
        if (stroke.smoothed) {
          final mid = (previous + p) / 2;
          stroke.path.quadraticBezierTo(
            previous.dx,
            previous.dy,
            mid.dx,
            mid.dy,
          );
        } else {
          stroke.path.lineTo(p.dx, p.dy);
        }
      }
      stroke.path.lineTo(points.last.dx, points.last.dy);
    }
    return stroke;
  }

  static const holdDuration = Duration(milliseconds: 650);

  /// Exposed read-only for feedback and deterministic gesture tests.
  SketchShape? get activeShape => _corrected?.shape?.kind;

  void configureShapes({
    required bool enabled,
    required bool snap,
    required bool fill,
  }) {
    drawAndHold = enabled;
    snapToShapes = snap;
    fillShapes = fill;
    if (!enabled) _holdTimer?.cancel();
  }

  ui.Picture? _picture;

  /// Strokes as they were when the current stroke-erase gesture began.
  List<DrawingStroke>? _beforeErase;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  bool get isEmpty => _strokes.isEmpty && _active == null;

  /// Fast toolbar check. Export also checks actual pixels, since partial
  /// erasers or strokes outside the paper can leave an apparently empty page.
  bool get hasInk => _strokes.any((s) => !s.erase && s.color.a > 0);
  int get strokeCount => _strokes.length;

  void begin(
    Offset point,
    Color color,
    double width,
    DrawingTool tool, {
    double inputScale = 1,
  }) {
    if (_active != null) return;
    _active = DrawingStroke(point, color, width, tool == DrawingTool.eraser);
    _active!.smoothed = stabilize && tool != DrawingTool.eraser;
    _corrected = null;
    _inputScale = inputScale;
    _holdAnchor = point;
    notifyListeners();
  }

  void extend(Offset point) {
    final active = _active;
    if (active == null) return;
    // Ignore tiny Pencil tremors once snapped. Larger movement resumes the
    // original freehand stroke, so correction never traps the pen.
    final moved = (point - _holdAnchor!).distance * _inputScale > 4;
    if (_corrected != null && !moved) return;
    if (moved) {
      _corrected = null;
      _holdAnchor = point;
      _holdTimer?.cancel();
      if (drawAndHold && !active.erase) {
        _holdTimer = Timer(holdDuration, _recognizeHeldStroke);
      }
    }
    if (active.smoothed) {
      final previous = active.points.last;
      final mid = (previous + point) / 2;
      active.path.quadraticBezierTo(previous.dx, previous.dy, mid.dx, mid.dy);
    } else {
      active.path.lineTo(point.dx, point.dy);
    }
    active.points.add(point);
    active.isDot = false;
    notifyListeners();
  }

  void _recognizeHeldStroke() {
    final raw = _active;
    if (!drawAndHold || raw == null || raw.erase) return;
    var shape = ShapeRecognizer.recognize(raw.points, scale: _inputScale);
    if (shape == null) return;
    if (snapToShapes && shape.kind == SketchShape.line) {
      final snapped = shape.points.map(_snapEndpoint).toList();
      if ((snapped.last - snapped.first).distance * _inputScale >= 24) {
        shape = RecognizedShape(SketchShape.line, snapped);
      }
    }
    _corrected = DrawingStroke(shape.points.first, raw.color, raw.width, false)
      ..isDot = false
      ..shape = shape
      ..filled = fillShapes && shape.closed;
    _corrected!.path
      ..reset()
      ..addPath(shape.path, Offset.zero);
    _corrected!.points
      ..clear()
      ..addAll(shape.points)
      ..addAll(shape.closed ? [shape.points.first] : <Offset>[]);
    notifyListeners();
  }

  Offset _snapEndpoint(Offset point) {
    var closest = point;
    var distance = 12 / _inputScale;
    for (var i = 0; i < _strokes.length; i++) {
      final shape = _strokes[i].shape;
      if (shape == null) continue;
      final anchors = shape.kind == SketchShape.ellipse
          ? [for (var j = 0; j < shape.points.length; j += 32) shape.points[j]]
          : shape.points;
      for (final anchor in anchors) {
        final d = (point - anchor).distance;
        if (d < distance &&
            !_strokes.skip(i + 1).any((s) => s.erase && s.touches(anchor, 0))) {
          closest = anchor;
          distance = d;
        }
      }
    }
    return closest;
  }

  /// Lifts every visible stroke the eraser touches. One gesture is one
  /// undo step, however many strokes it removes.
  void eraseStrokesAt(Offset point, double radius) {
    final hit = _strokes
        .where((s) => !s.erase && s.touches(point, radius))
        .toList();
    if (hit.isEmpty) return;
    _beforeErase ??= List.of(_strokes);
    _strokes.removeWhere(hit.contains);
    _changed(record: false);
  }

  void endStrokeErase() {
    final before = _beforeErase;
    if (before == null) return;
    _beforeErase = null;
    _undo.add(before);
    _redo.clear();
    history.value++;
  }

  /// A two-finger navigation gesture must roll back the first finger's eraser.
  void cancelStrokeErase() {
    final before = _beforeErase;
    if (before == null) return;
    _beforeErase = null;
    _strokes
      ..clear()
      ..addAll(before);
    _changed();
  }

  void end() {
    _holdTimer?.cancel();
    if (_active == null) return;
    if (!_active!.isDot) {
      _active!.path.lineTo(_active!.points.last.dx, _active!.points.last.dy);
    }
    _remember();
    // First undo restores the hand-drawn line; a second removes the stroke.
    if (_corrected != null) _undo.add([..._strokes, _active!]);
    _strokes.add(_corrected ?? _active!);
    _active = null;
    _corrected = null;
    _changed();
  }

  void cancel() {
    _holdTimer?.cancel();
    _active = null;
    _corrected = null;
    notifyListeners();
  }

  void _remember() {
    _undo.add(List.of(_strokes));
    _redo.clear();
  }

  void clear() {
    if (_strokes.isEmpty) return;
    _remember();
    _strokes.clear();
    _changed();
  }

  void undo() {
    if (!canUndo) return;
    _redo.add(List.of(_strokes));
    _strokes
      ..clear()
      ..addAll(_undo.removeLast());
    _changed();
  }

  void redo() {
    if (!canRedo) return;
    _undo.add(List.of(_strokes));
    _strokes
      ..clear()
      ..addAll(_redo.removeLast());
    _changed();
  }

  void _changed({bool record = true}) {
    _picture?.dispose();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    for (final stroke in _strokes) {
      stroke.paint(canvas);
    }
    _picture = recorder.endRecording();
    if (record) history.value++;
    notifyListeners();
  }

  void paint(Canvas canvas, Size size) {
    // One isolated ink layer lets erasers reveal the paper/grid below it.
    canvas.saveLayer(Offset.zero & size, Paint());
    if (_picture != null) canvas.drawPicture(_picture!);
    (_corrected ?? _active)?.paint(canvas);
    canvas.restore();
  }

  /// Transparent ink only, never the toolbar, paper grid or zoom transform.
  /// Return null for fully erased/transparent/clipped drawings.
  Future<Uint8List?> exportInk(Size size, {int maxDimension = 4096}) async {
    if (!hasInk || size.isEmpty || !size.isFinite) return null;
    final scale = math.min(2.0, maxDimension / size.longestSide);
    final width = math.max(1, (size.width * scale).ceil());
    final height = math.max(1, (size.height * scale).ceil());
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(scale);
    // Export fresh vector commands rather than nesting the on-screen picture.
    // This also makes the snapshot independent of the live repaint cache.
    canvas.saveLayer(Offset.zero & size, Paint());
    for (final stroke in _strokes) {
      stroke.paint(canvas);
    }
    canvas.restore();
    final picture = recorder.endRecording();
    ui.Image? image;
    try {
      image = await picture.toImage(width, height);
      final rgba = await image.toByteData();
      if (rgba == null) throw StateError('Could not read drawing pixels');
      var visible = false;
      for (var i = 3; i < rgba.lengthInBytes; i += 4) {
        if (rgba.getUint8(i) != 0) {
          visible = true;
          break;
        }
      }
      if (!visible) return null;
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) throw StateError('Could not encode drawing');
      return png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes);
    } finally {
      image?.dispose();
      picture.dispose();
    }
  }

  /// Test a tight ink region at 2× resolution. Downsampling the whole iPad
  /// page can erase small dots/thin strokes during validation on Impeller.
  /// Checking only this region also avoids encoding a PNG after every stroke.
  Future<bool> hasVisibleInk(Size size) async {
    if (!hasInk || size.isEmpty || !size.isFinite) return false;
    Rect? bounds;
    for (final stroke in _strokes) {
      if (stroke.erase || stroke.color.a == 0) continue;
      final area = stroke.isDot
          ? Rect.fromCircle(center: stroke.start, radius: stroke.width / 2)
          : stroke.path.getBounds().inflate(stroke.width / 2);
      bounds = bounds == null ? area : bounds.expandToInclude(area);
    }
    final region = bounds?.intersect(Offset.zero & size);
    if (region == null || region.isEmpty) return false;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..scale(2)
      ..translate(-region.left, -region.top)
      ..saveLayer(region, Paint());
    for (final stroke in _strokes) {
      stroke.paint(canvas);
    }
    canvas.restore();
    final picture = recorder.endRecording();
    ui.Image? image;
    try {
      image = await picture.toImage(
        math.max(1, (region.width * 2).ceil()),
        math.max(1, (region.height * 2).ceil()),
      );
      final rgba = await image.toByteData();
      if (rgba == null) throw StateError('Could not read drawing pixels');
      for (var i = 3; i < rgba.lengthInBytes; i += 4) {
        if (rgba.getUint8(i) != 0) return true;
      }
      return false;
    } finally {
      image?.dispose();
      picture.dispose();
    }
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _picture?.dispose();
    history.dispose();
    super.dispose();
  }
}

class InkPainter extends CustomPainter {
  InkPainter(this.controller) : super(repaint: controller);
  final DrawingController controller;
  @override
  void paint(Canvas canvas, Size size) => controller.paint(canvas, size);
  @override
  bool shouldRepaint(InkPainter oldDelegate) =>
      oldDelegate.controller != controller;
}
