import '../../util/art_cache.dart';

import 'dart:convert';
import '../../data/art_source.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'figure_motion.dart';

/// Where a flat (PNG) character's face is: which way it looks, its head,
/// eyes, mouth and cheeks, in pixels of the picture. It sits next to the
/// picture as `<name>.face.json` (see docs/CHARACTER_RIG.md) — the
/// character generator writes it along with the picture.
///
/// A flat picture can't move its own eyes or mouth, so the house draws
/// them over it: eyelids in the colour of the skin around each eye, a
/// mouth that opens and chews, and a blush that comes up with a full
/// mouth.
class FaceMap {
  const FaceMap({
    required this.size,
    this.facing = 0,
    this.head,
    this.eyes = const [],
    this.mouth,
    this.cheeks = const [],
    this.skins = const [],
  });

  /// The picture's size in pixels; everything else is in these pixels.
  final Size size;

  /// -1 looking left, 1 right, 0 straight at us.
  final double facing;
  final Rect? head;

  /// Centre and radius of each eye.
  final List<(Offset, double)> eyes;
  final Rect? mouth;
  final List<(Offset, double)> cheeks;

  /// The skin colour around each eye, for its eyelid.
  final List<Color> skins;

  /// The same face on the picture cut to [crop] (fractions of this one).
  FaceMap cropped(Rect crop) {
    final cut = Rect.fromLTRB(
      crop.left * size.width,
      crop.top * size.height,
      crop.right * size.width,
      crop.bottom * size.height,
    );
    final by = -cut.topLeft;
    return FaceMap(
      size: cut.size,
      facing: facing,
      head: head?.shift(by),
      eyes: [for (final (c, r) in eyes) (c + by, r)],
      mouth: mouth?.shift(by),
      cheeks: [for (final (c, r) in cheeks) (c + by, r)],
      skins: skins,
    );
  }

  /// [r] as fractions of the picture.
  Rect fraction(Rect r) => Rect.fromLTRB(
    r.left / size.width,
    r.top / size.height,
    r.right / size.width,
    r.bottom / size.height,
  );

  /// Reads the JSON; null if it isn't a face map.
  static FaceMap? fromJson(Object? json) {
    if (json is! Map) return null;
    List<double>? numbers(Object? v, int n) {
      if (v is! List || v.length != n || v.any((e) => e is! num)) return null;
      return [for (final e in v) (e as num).toDouble()];
    }

    final size = numbers(json['size'], 2);
    if (size == null || size[0] <= 0 || size[1] <= 0) return null;
    Rect? box(Object? v) => switch (numbers(v, 4)) {
      [final x, final y, final w, final h] => Rect.fromLTWH(x, y, w, h),
      _ => null,
    };
    List<(Offset, double)> circles(Object? v) => [
      if (v is List)
        for (final e in v)
          if (numbers(e, 3) case [final x, final y, final r]) (Offset(x, y), r),
    ];
    final mouth = numbers(json['mouth'], 4);
    return FaceMap(
      size: Size(size[0], size[1]),
      facing: switch (json['facing']) {
        'left' => -1,
        'right' => 1,
        _ => 0,
      },
      head: box(json['head']),
      eyes: circles(json['eyes']),
      // Given by its centre, as a mouth is easiest to point at.
      mouth: mouth == null
          ? null
          : Rect.fromCenter(
              center: Offset(mouth[0], mouth[1]),
              width: mouth[2],
              height: mouth[3],
            ),
      cheeks: circles(json['cheeks']),
    );
  }
}

final _faces = ArtCache<String, Future<FaceMap?>>(96);

/// Face maps that came with a friend rather than as a file beside its
/// picture: the character service sends one with each friend it makes.
final _given = ArtCache<String, Object>(96);

/// Uses [json] as the face map of the picture at [assetPath] (the format of
/// a `.face.json`). Giving the same map again changes nothing; a different
/// one replaces what was read before (see [faceMapRevision]).
void giveFaceMap(String assetPath, Object? json) {
  if (json == null) return;
  final text = jsonEncode(json);
  if (_givenText[assetPath] == text) return;
  _givenText[assetPath] = text;
  _given[assetPath] = json;
  _faces.remove(assetPath);
  _revisions[assetPath] = faceMapRevision(assetPath) + 1;
}

final _givenText = ArtCache<String, String>(96);
final _revisions = ArtCache<String, int>(96);

/// Goes up each time a different face map is given for [assetPath], so what
/// was worked out from the old one (where the mouth is) is worked out again.
int faceMapRevision(String assetPath) => _revisions[assetPath] ?? 0;

/// The face map given for the picture, or the one beside a PNG picture
/// (`x.png` → `x.face.json`, from the same place: asset, file or URL), or
/// null when it has none.
Future<FaceMap?> faceMapFor(String assetPath) =>
    _faces[assetPath] ??= _loadFace(assetPath);

Future<FaceMap?> _loadFace(String assetPath) async {
  final Object? json;
  if (_given[assetPath] case final given?) {
    json = given;
  } else {
    if (!isPngArt(assetPath)) return null;
    try {
      json = jsonDecode(
        await loadArtString(artSibling(assetPath, '.png', '.face.json')),
      );
    } catch (_) {
      return null;
    }
  }
  final read = FaceMap.fromJson(json);
  if (read == null) return null;
  // The picture may be shown cut to its figure; so is its face.
  final crop = await artCropOf(assetPath);
  final face = crop == null ? read : read.cropped(crop);
  try {
    return await _checked(assetPath, face);
  } catch (_) {
    return face;
  }
}

/// Checks the map against the picture — an eye that isn't on the drawing
/// (a generator's slip) is dropped rather than drawn in mid-air — and
/// finds the skin colour just outside each eye: the most common opaque
/// colour on a ring around it.
Future<FaceMap> _checked(String assetPath, FaceMap face) async {
  final codec = await ui.instantiateImageCodec(
    await loadArtBytes(assetPath),
    targetWidth: 480,
  );
  final image = (await codec.getNextFrame()).image;
  codec.dispose();
  final w = image.width, h = image.height;
  final bytes = await image.toByteData();
  image.dispose();
  if (bytes == null) return face;
  final scale = w / face.size.width;
  bool drawn(Offset p) {
    final x = (p.dx * scale).round(), y = (p.dy * scale).round();
    return x >= 0 &&
        y >= 0 &&
        x < w &&
        y < h &&
        bytes.getUint8((y * w + x) * 4 + 3) > 128;
  }

  final eyes = [
    for (final eye in face.eyes)
      if (drawn(eye.$1)) eye,
  ];
  final skins = [
    for (final (centre, r) in eyes)
      _commonColour(bytes, w, h, [
        for (var i = 0; i < 24; i++)
          Offset(
                centre.dx + math.cos(i / 24 * 2 * math.pi) * r * 1.7,
                centre.dy + math.sin(i / 24 * 2 * math.pi) * r * 1.7,
              ) *
              scale,
      ]),
  ];
  return FaceMap(
    size: face.size,
    facing: face.facing,
    head: face.head,
    eyes: eyes,
    mouth: face.mouth,
    cheeks: face.cheeks,
    skins: skins,
  );
}

Color _commonColour(ByteData bytes, int w, int h, List<Offset> points) {
  final counts = <int, int>{};
  for (final p in points) {
    final x = p.dx.round(), y = p.dy.round();
    if (x < 0 || y < 0 || x >= w || y >= h) continue;
    final i = (y * w + x) * 4;
    if (bytes.getUint8(i + 3) < 200) continue;
    // Close shades count as one.
    final key =
        (bytes.getUint8(i) >> 3) << 10 |
        (bytes.getUint8(i + 1) >> 3) << 5 |
        bytes.getUint8(i + 2) >> 3;
    counts[key] = (counts[key] ?? 0) + 1;
  }
  if (counts.isEmpty) return const Color(0xFFFFE0B0);
  final key = counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  int channel(int shift) => ((key >> shift) & 31) << 3 | 4;
  return Color.fromARGB(255, channel(10), channel(5), channel(0));
}

/// The face drawn over a flat picture, moving with [pose]: eyelids that
/// blink and squeeze shut (with a line of lashes), and cheeks can blush.
/// The baked-in PNG mouth is preserved rather than painted over. At rest it draws
/// nothing, so the picture shows as drawn.
class FacePainter extends CustomPainter {
  FacePainter(this.face, this.pose) : super(repaint: pose);
  final FaceMap face;
  final ValueListenable<FigurePose> pose;

  static const _lash = Color(0xFF4A3434);

  @override
  void paint(Canvas canvas, Size size) {
    final p = pose.value;
    final s = size.width / face.size.width;
    canvas.save();
    canvas.scale(s, size.height / face.size.height);

    final shut = (1 - p.eyes).clamp(0.0, 1.0);
    if (shut > .03) {
      for (final (i, (centre, r)) in face.eyes.indexed) {
        final eye = Rect.fromCircle(center: centre, radius: r * 1.15);
        final edge = eye.top + eye.height * shut;
        canvas
          ..save()
          ..clipPath(Path()..addOval(eye))
          ..drawRect(
            Rect.fromLTRB(eye.left, eye.top, eye.right, edge + 1),
            Paint()
              ..color = i < face.skins.length
                  ? face.skins[i]
                  : const Color(0xFFFFE0B0),
          )
          ..restore();
        // Mostly shut: a curved line of lashes along the lid — sagging (◡)
        // when sleepy, arched (^) when shut in a smile.
        if (shut > .5) {
          final sag = r * .35 * shut;
          final sleepy = math.min(edge, eye.bottom - r * .2);
          final y = sleepy + (centre.dy + r * .2 - sleepy) * p.joy;
          final bend = sag * (1 - 2.4 * p.joy);
          canvas.drawPath(
            Path()
              ..moveTo(eye.left + r * .1, y)
              ..quadraticBezierTo(
                eye.center.dx,
                y + bend,
                eye.right - r * .1,
                y,
              ),
            Paint()
              ..color = _lash
              ..style = PaintingStyle.stroke
              ..strokeWidth = r * .26
              ..strokeCap = StrokeCap.round,
          );
        }
      }
    }

    // Wide with delight or surprise: a twinkle in each eye.
    if (p.eyes > 1.04 && shut < .03) {
      final glow = ((p.eyes - 1) / .2).clamp(0.0, 1.0);
      for (final (centre, r) in face.eyes) {
        _twinkle(canvas, centre + Offset(r * .38, -r * .42), r * .34 * glow);
      }
    }

    // PNG mouth pixels are baked into the art. Do not draw a second mouth.
    // SVG rigs still animate their separate mouth layer.

    if (p.cheeks > .02) {
      for (final (centre, r) in face.cheeks) {
        canvas.drawCircle(
          centre,
          r * (1 + .25 * p.cheeks),
          Paint()
            ..color = const Color(
              0xFFFF7F8F,
            ).withValues(alpha: (.45 * p.cheeks).clamp(0.0, .5))
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * .25),
        );
      }
    }
    canvas.restore();
  }

  /// A little four-pointed white star.
  static void _twinkle(Canvas canvas, Offset c, double size) {
    if (size <= .5) return;
    final thin = size * .28;
    canvas.drawPath(
      Path()
        ..moveTo(c.dx, c.dy - size)
        ..quadraticBezierTo(c.dx + thin, c.dy - thin, c.dx + size, c.dy)
        ..quadraticBezierTo(c.dx + thin, c.dy + thin, c.dx, c.dy + size)
        ..quadraticBezierTo(c.dx - thin, c.dy + thin, c.dx - size, c.dy)
        ..quadraticBezierTo(c.dx - thin, c.dy - thin, c.dx, c.dy - size)
        ..close(),
      Paint()..color = Colors.white.withValues(alpha: .95),
    );
  }

  @override
  bool shouldRepaint(FacePainter old) => old.face != face || old.pose != pose;
}
