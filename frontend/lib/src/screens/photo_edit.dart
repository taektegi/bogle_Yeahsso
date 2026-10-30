import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import '../data/photo_preparation.dart';

/// How a photo is edited before it becomes a friend: turned a quarter at a
/// time, cut down to [crop] (fractions of the turned photo), and brightened.
typedef PhotoEdit = ({int quarterTurns, Rect crop, bool brighten});

const uneditedPhoto = (
  quarterTurns: 0,
  crop: Rect.fromLTRB(0, 0, 1, 1),
  brighten: false,
);

bool isUnedited(PhotoEdit e) =>
    e.quarterTurns % 4 == 0 && e.crop == uneditedPhoto.crop && !e.brighten;

/// [crop] after the photo turns a quarter clockwise: what was at the top
/// is now on the right.
Rect turnCrop(Rect crop) =>
    Rect.fromLTRB(1 - crop.bottom, crop.left, 1 - crop.top, crop.right);

/// A photo's width and height without decoding all of it.
Future<Size> photoSize(Uint8List bytes) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  final descriptor = await ui.ImageDescriptor.encoded(buffer);
  final size = Size(descriptor.width.toDouble(), descriptor.height.toDouble());
  descriptor.dispose();
  buffer.dispose();
  return size;
}

/// Brighter and a little punchier: grey pencil on grey paper turns into
/// dark lines on white, which the generator reads better.
const brightenMatrix = <double>[
  1.16, 0, 0, 0, -6, //
  0, 1.16, 0, 0, -6, //
  0, 0, 1.16, 0, -6, //
  0, 0, 0, 1, 0, //
];

/// Applies [edit] to [bytes]: a PNG no longer than [maxSide] on its long
/// side. The photo as it was comes back untouched when nothing changed.
Future<Uint8List> renderPhotoEdit(
  Uint8List bytes,
  PhotoEdit edit, {
  int maxSide = 2048,
}) async {
  if (isUnedited(edit)) return bytes;
  final codec = await ui.instantiateImageCodec(bytes);
  final source = (await codec.getNextFrame()).image;
  codec.dispose();
  final turns = edit.quarterTurns % 4;
  final w = source.width.toDouble(), h = source.height.toDouble();
  final turned = turns.isOdd ? Size(h, w) : Size(w, h);
  final cut = Rect.fromLTRB(
    edit.crop.left * turned.width,
    edit.crop.top * turned.height,
    edit.crop.right * turned.width,
    edit.crop.bottom * turned.height,
  );
  final scale = math.min(1.0, maxSide / math.max(cut.width, cut.height));
  final out = Size(
    (cut.width * scale).roundToDouble(),
    (cut.height * scale).roundToDouble(),
  );
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..scale(scale)
    ..translate(-cut.left, -cut.top)
    // Turn the photo into the turned frame: rotate about the origin, then
    // bring it back into view.
    ..translate(
      turns == 1 || turns == 2 ? turned.width : 0,
      turns == 2 || turns == 3 ? turned.height : 0,
    )
    ..rotate(turns * math.pi / 2);
  canvas.drawImage(
    source,
    Offset.zero,
    Paint()
      ..filterQuality = FilterQuality.high
      ..colorFilter = edit.brighten
          ? const ColorFilter.matrix(brightenMatrix)
          : null,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(out.width.toInt(), out.height.toInt());
  picture.dispose();
  source.dispose();
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return png!.buffer.asUint8List();
}

/// Production submission always validates and normalizes the resulting format.
Future<Uint8List> renderPhotoForGeneration(
  Uint8List bytes,
  PhotoEdit edit,
) async {
  // Bound the decoder before crop/rotation allocates intermediate surfaces.
  final normalized = await PhotoPreparation.normalize(bytes);
  if (isUnedited(edit)) return normalized;
  return PhotoPreparation.normalize(await renderPhotoEdit(normalized, edit));
}

/// The photo as edited, laid out at its edited shape (fitted inside the
/// incoming constraints). Until [size] is known it shows the whole photo.
class EditedPhoto extends StatelessWidget {
  const EditedPhoto({
    super.key,
    required this.bytes,
    required this.edit,
    this.size,
  });
  final Uint8List bytes;
  final PhotoEdit edit;
  final Size? size;

  @override
  Widget build(BuildContext context) {
    Widget photo = RotatedBox(
      quarterTurns: edit.quarterTurns % 4,
      child: Image.memory(
        bytes,
        key: const ValueKey('photo-checked'),
        fit: BoxFit.fill,
        gaplessPlayback: true,
        semanticLabel: '찍은 그림 사진',
      ),
    );
    if (edit.brighten) {
      photo = ColorFiltered(
        colorFilter: const ColorFilter.matrix(brightenMatrix),
        child: photo,
      );
    }
    final size = this.size;
    if (size == null) return photo;
    final turned = edit.quarterTurns.isOdd ? size.flipped : size;
    final crop = edit.crop;
    return AspectRatio(
      aspectRatio: turned.aspectRatio * crop.width / crop.height,
      child: LayoutBuilder(
        builder: (context, box) {
          final whole = Size(
            box.maxWidth / crop.width,
            box.maxHeight / crop.height,
          );
          return ClipRect(
            child: Stack(
              children: [
                Positioned(
                  left: -crop.left * whole.width,
                  top: -crop.top * whole.height,
                  width: whole.width,
                  height: whole.height,
                  child: photo,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Choosing what to keep: the whole (turned) photo with the kept part
/// framed. Drag a corner or an edge to resize it, or inside it to move it;
/// the rest is dimmed, and a rule-of-thirds grid shows while dragging.
class CropEditor extends StatefulWidget {
  const CropEditor({
    super.key,
    required this.bytes,
    required this.size,
    required this.edit,
    required this.onCrop,
  });
  final Uint8List bytes;
  final Size size;
  final PhotoEdit edit;
  final ValueChanged<Rect> onCrop;

  /// The smallest part that can be kept, per side.
  static const smallest = .15;

  @override
  State<CropEditor> createState() => _CropEditorState();
}

enum _Grip {
  topLeft,
  topRight,
  bottomRight,
  bottomLeft,
  top,
  right,
  bottom,
  left,
  move,
}

class _CropEditorState extends State<CropEditor> {
  _Grip? _grip;
  late Rect _crop = widget.edit.crop;

  @override
  void didUpdateWidget(CropEditor old) {
    super.didUpdateWidget(old);
    if (_grip == null) _crop = widget.edit.crop;
  }

  _Grip? _gripAt(Offset p, Size box) {
    final r = Rect.fromLTRB(
      _crop.left * box.width,
      _crop.top * box.height,
      _crop.right * box.width,
      _crop.bottom * box.height,
    );
    const reach = 36.0;
    final corners = {
      _Grip.topLeft: r.topLeft,
      _Grip.topRight: r.topRight,
      _Grip.bottomRight: r.bottomRight,
      _Grip.bottomLeft: r.bottomLeft,
    };
    for (final MapEntry(key: grip, value: at) in corners.entries) {
      if ((p - at).distance < reach) return grip;
    }
    final near = r.inflate(reach / 2);
    if (!near.contains(p)) return null;
    if ((p.dy - r.top).abs() < reach / 2) return _Grip.top;
    if ((p.dy - r.bottom).abs() < reach / 2) return _Grip.bottom;
    if ((p.dx - r.left).abs() < reach / 2) return _Grip.left;
    if ((p.dx - r.right).abs() < reach / 2) return _Grip.right;
    return r.contains(p) ? _Grip.move : null;
  }

  void _drag(Offset delta, Size box) {
    final dx = delta.dx / box.width, dy = delta.dy / box.height;
    const min = CropEditor.smallest;
    var l = _crop.left, t = _crop.top, r = _crop.right, b = _crop.bottom;
    switch (_grip) {
      case _Grip.move:
        final w = r - l, h = b - t;
        l = (l + dx).clamp(0.0, 1 - w);
        t = (t + dy).clamp(0.0, 1 - h);
        r = l + w;
        b = t + h;
      case null:
        return;
      default:
        final g = _grip!;
        if (g == _Grip.topLeft || g == _Grip.left || g == _Grip.bottomLeft) {
          l = (l + dx).clamp(0.0, r - min);
        }
        if (g == _Grip.topRight || g == _Grip.right || g == _Grip.bottomRight) {
          r = (r + dx).clamp(l + min, 1.0);
        }
        if (g == _Grip.topLeft || g == _Grip.top || g == _Grip.topRight) {
          t = (t + dy).clamp(0.0, b - min);
        }
        if (g == _Grip.bottomLeft ||
            g == _Grip.bottom ||
            g == _Grip.bottomRight) {
          b = (b + dy).clamp(t + min, 1.0);
        }
    }
    setState(() => _crop = Rect.fromLTRB(l, t, r, b));
  }

  @override
  Widget build(BuildContext context) {
    final photo = EditedPhoto(
      bytes: widget.bytes,
      size: widget.size,
      edit: (
        quarterTurns: widget.edit.quarterTurns,
        crop: uneditedPhoto.crop,
        brighten: widget.edit.brighten,
      ),
    );
    return LayoutBuilder(
      builder: (context, box) {
        final turned = widget.edit.quarterTurns.isOdd
            ? widget.size.flipped
            : widget.size;
        final fitted = applyBoxFit(
          BoxFit.contain,
          turned,
          box.biggest,
        ).destination;
        return Center(
          child: SizedBox.fromSize(
            size: fitted,
            child: GestureDetector(
              key: const ValueKey('photo-crop-area'),
              behavior: HitTestBehavior.opaque,
              onPanStart: (d) =>
                  setState(() => _grip = _gripAt(d.localPosition, fitted)),
              onPanUpdate: (d) => _drag(d.delta, fitted),
              onPanEnd: (_) {
                setState(() => _grip = null);
                widget.onCrop(_crop);
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  photo,
                  CustomPaint(
                    painter: _CropFrame(_crop, dragging: _grip != null),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CropFrame extends CustomPainter {
  _CropFrame(this.crop, {required this.dragging});
  final Rect crop;
  final bool dragging;

  @override
  void paint(Canvas canvas, Size s) {
    final r = Rect.fromLTRB(
      crop.left * s.width,
      crop.top * s.height,
      crop.right * s.width,
      crop.bottom * s.height,
    );
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & s)
        ..addRect(r),
      Paint()..color = Colors.black.withValues(alpha: .5),
    );
    final line = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(r, line);
    if (dragging) {
      final thin = Paint()
        ..color = Colors.white.withValues(alpha: .6)
        ..strokeWidth = 1;
      for (final f in [1 / 3, 2 / 3]) {
        canvas
          ..drawLine(
            Offset(r.left + r.width * f, r.top),
            Offset(r.left + r.width * f, r.bottom),
            thin,
          )
          ..drawLine(
            Offset(r.left, r.top + r.height * f),
            Offset(r.right, r.top + r.height * f),
            thin,
          );
      }
    }
    // Thick L-shaped handles at the corners, short bars mid-edge.
    final handle = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    final arm = math.min(28.0, math.min(r.width, r.height) / 3);
    for (final (c, dx, dy) in [
      (r.topLeft, 1.0, 1.0),
      (r.topRight, -1.0, 1.0),
      (r.bottomRight, -1.0, -1.0),
      (r.bottomLeft, 1.0, -1.0),
    ]) {
      canvas.drawPath(
        Path()
          ..moveTo(c.dx, c.dy + dy * arm)
          ..lineTo(c.dx, c.dy)
          ..lineTo(c.dx + dx * arm, c.dy),
        handle,
      );
    }
    final bar = math.min(20.0, math.min(r.width, r.height) / 4);
    for (final (c, horizontal) in [
      (r.topCenter, true),
      (r.bottomCenter, true),
      (r.centerLeft, false),
      (r.centerRight, false),
    ]) {
      canvas.drawLine(
        c - (horizontal ? Offset(bar, 0) : Offset(0, bar)),
        c + (horizontal ? Offset(bar, 0) : Offset(0, bar)),
        handle,
      );
    }
  }

  @override
  bool shouldRepaint(_CropFrame old) =>
      old.crop != crop || old.dragging != dragging;
}
