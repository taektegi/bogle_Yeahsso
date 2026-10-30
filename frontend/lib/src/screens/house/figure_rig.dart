import '../../util/art_cache.dart';

import 'dart:math' as math;
import '../../data/art_source.dart';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:xml/xml.dart';

import 'figure_motion.dart';

/// Parts of a character drawing that move on their own. A character SVG —
/// drawn by hand in Figma or made by the character generator — marks them
/// with these group ids (see docs/CHARACTER_RIG.md); anything left unmarked
/// is the body. Every part is optional: a drawing with none still hops,
/// dances and waves with its whole body.
enum RigPart {
  eyes('bogle-eyes'),
  mouth('bogle-mouth'),
  cheeks('bogle-cheeks'),
  armLeft('bogle-arm-left'),
  armRight('bogle-arm-right');

  const RigPart(this.id);
  final String id;
}

/// One moving part: its own SVG (the whole canvas, only this part drawn),
/// where it sits and the point it turns or opens about, both as fractions
/// of the canvas.
class RigLayer {
  const RigLayer(this.svg, this.bounds, this.pivot);
  final String svg;
  final Rect bounds;
  final Offset pivot;
}

/// A character drawing cut into its moving parts. Stacked in drawing order
/// the layers draw the original picture exactly.
class FigureRig {
  const FigureRig({
    required this.canvas,
    required this.body,
    required this.layers,
    this.facing = 0,
  });

  final Size canvas;

  /// Which way the drawing looks (`data-bogle-facing` on the svg: "left"
  /// or "right"); 0 straight at us.
  final double facing;

  /// Everything that isn't a marked part.
  final String body;

  /// The marked parts, in drawing order.
  final Map<RigPart, RigLayer> layers;

  bool get hasArms =>
      layers.containsKey(RigPart.armLeft) ||
      layers.containsKey(RigPart.armRight);
  bool get hasFace =>
      layers.containsKey(RigPart.eyes) || layers.containsKey(RigPart.mouth);

  /// Cuts [svg] into its parts, or null when it marks none. [measure]
  /// finds where a part is drawn (fractions of the canvas).
  static Future<FigureRig?> parse(
    String svg, {
    Future<Rect?> Function(String svg) measure = measureSvg,
  }) async {
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(svg);
    } on XmlException {
      return null;
    }
    final root = doc.rootElement;
    final canvas = _canvas(root);
    if (canvas == null) return null;
    final found = {
      for (final part in RigPart.values) part: ?_byId(doc, part.id),
    };
    if (found.isEmpty) return null;

    final order = doc.descendantElements.toList();
    final parts = found.keys.toList()
      ..sort((a, b) => order.indexOf(found[a]!) - order.indexOf(found[b]!));
    final layers = <RigPart, RigLayer>{};
    for (final part in parts) {
      final only = _only(doc, part.id);
      final bounds = await measure(only);
      if (bounds == null) continue;
      layers[part] = RigLayer(
        only,
        bounds,
        _pivot(part, found[part]!, bounds, canvas),
      );
    }
    if (layers.isEmpty) return null;
    return FigureRig(
      canvas: canvas,
      body: _without(doc, [for (final p in layers.keys) p.id]),
      layers: layers,
      facing: switch (root.getAttribute('data-bogle-facing')) {
        'left' => -1,
        'right' => 1,
        _ => 0,
      },
    );
  }

  static Size? _canvas(XmlElement svg) {
    final box = svg.getAttribute('viewBox')?.trim().split(RegExp(r'[\s,]+'));
    if (box != null && box.length == 4) {
      final w = double.tryParse(box[2]), h = double.tryParse(box[3]);
      if (w != null && h != null && w > 0 && h > 0) return Size(w, h);
    }
    final w = double.tryParse(svg.getAttribute('width') ?? '');
    final h = double.tryParse(svg.getAttribute('height') ?? '');
    return w != null && h != null && w > 0 && h > 0 ? Size(w, h) : null;
  }

  static XmlElement? _byId(XmlNode doc, String id) => doc.descendantElements
      .where((e) => e.getAttribute('id') == id)
      .firstOrNull;

  /// Where a part turns or opens about. An arm may say where its shoulder
  /// is (`data-bogle-pivot="x y"`, canvas units); otherwise it's the arm's
  /// lowest corner nearest the middle. Eyes blink toward their middle line
  /// and a mouth opens down from its top lip.
  static Offset _pivot(
    RigPart part,
    XmlElement element,
    Rect bounds,
    Size canvas,
  ) {
    final given = element
        .getAttribute('data-bogle-pivot')
        ?.trim()
        .split(RegExp(r'[\s,]+'))
        .map(double.tryParse)
        .toList();
    if (given != null && given.length == 2 && !given.contains(null)) {
      return Offset(given[0]! / canvas.width, given[1]! / canvas.height);
    }
    return switch (part) {
      RigPart.armLeft => Offset(bounds.right, bounds.top + bounds.height * .85),
      RigPart.armRight => Offset(bounds.left, bounds.top + bounds.height * .85),
      RigPart.mouth => bounds.topCenter,
      _ => bounds.center,
    };
  }

  /// The drawing with only the part [id] (and what it needs, like `defs`).
  static String _only(XmlDocument doc, String id) {
    final copy = doc.copy();
    final part = _byId(copy, id)!;
    final chain = {part, ...part.ancestorElements};
    for (final holder in part.ancestorElements) {
      for (final child in holder.childElements.toList()) {
        if (chain.contains(child) || _keep(child)) continue;
        child.remove();
      }
    }
    return copy.toXmlString();
  }

  static String _without(XmlDocument doc, List<String> ids) {
    final copy = doc.copy();
    for (final id in ids) {
      _byId(copy, id)?.remove();
    }
    return copy.toXmlString();
  }

  static bool _keep(XmlElement e) =>
      const {'defs', 'style', 'title', 'desc'}.contains(e.name.local);
}

final _rigs = ArtCache<String, Future<FigureRig?>>(32);

/// The rig for a friend's drawing, read once per drawing. Only SVG drawings
/// can have one; the rest move as a whole.
Future<FigureRig?> rigFor(String assetPath) =>
    _rigs[assetPath] ??= !isSvgArt(assetPath)
    ? Future.value()
    : loadArtString(
        assetPath,
      ).then(FigureRig.parse).catchError((Object _) => null);

/// Where [svg] is actually drawn, as fractions of its canvas; null when
/// nothing shows.
Future<Rect?> measureSvg(String svg) async {
  try {
    final info = await vg.loadPicture(SvgStringLoader(svg), null);
    final scale = 200 / math.max(info.size.width, info.size.height);
    final recorder = ui.PictureRecorder();
    Canvas(recorder)
      ..scale(scale)
      ..drawPicture(info.picture);
    final picture = recorder.endRecording();
    final w = (info.size.width * scale).ceil();
    final h = (info.size.height * scale).ceil();
    final image = await picture.toImage(w, h);
    picture.dispose();
    info.picture.dispose();
    final pixels = await image.toByteData();
    image.dispose();
    if (pixels == null) return null;
    var left = w, top = h, right = -1, bottom = -1;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        // Faint parts (cheeks at 40%) still count.
        if (pixels.getUint8((y * w + x) * 4 + 3) < 24) continue;
        left = math.min(left, x);
        right = math.max(right, x);
        top = math.min(top, y);
        bottom = math.max(bottom, y);
      }
    }
    if (right < 0) return null;
    return Rect.fromLTRB(left / w, top / h, (right + 1) / w, (bottom + 1) / h);
  } catch (_) {
    return null;
  }
}

/// A rigged drawing in [pose]: blinking eyes, a mouth that opens and chews,
/// cheeks that puff and arms that swing about their shoulders. Sized like
/// the plain drawing would be (fitted inside the incoming constraints,
/// keeping its shape).
class RiggedArtwork extends StatelessWidget {
  const RiggedArtwork({
    super.key,
    required this.rig,
    required this.pose,
    this.semanticsLabel,
  });

  final FigureRig rig;
  final FigurePose pose;
  final String? semanticsLabel;

  static Alignment _at(Offset f) => Alignment(f.dx * 2 - 1, f.dy * 2 - 1);

  Widget _part(RigPart part, RigLayer layer) {
    final picture = SvgPicture.string(layer.svg, fit: BoxFit.fill);
    final p = pose;
    final at = _at(layer.pivot);
    return switch (part) {
      // Squeezed shut toward their middle line; wider when surprised; they
      // slide a little to look sideways.
      RigPart.eyes => FractionalTranslation(
        translation: Offset(p.look * .035, 0),
        child: Transform(
          alignment: at,
          transform: Matrix4.diagonal3Values(math.max(1, p.eyes), p.eyes, 1),
          child: picture,
        ),
      ),
      // Opens down from the top lip into a round "아"; pressed flat and a
      // little wider when chewing with its mouth shut.
      RigPart.mouth => Transform(
        alignment: at,
        transform: Matrix4.diagonal3Values(
          p.mouth > 0 ? 1 + p.mouth * .08 : 1 - p.mouth * .16,
          math.max(.15, 1 + p.mouth * 1.25),
          1,
        ),
        child: picture,
      ),
      // Puffed cheeks bulge out to the sides.
      RigPart.cheeks => Transform(
        alignment: at,
        transform: Matrix4.diagonal3Values(
          1 + p.cheeks * .2,
          1 + p.cheeks * .16,
          1,
        ),
        child: picture,
      ),
      // Raising an arm turns its hand up over the shoulder.
      RigPart.armLeft => Transform.rotate(
        angle: p.armLeft,
        alignment: at,
        child: picture,
      ),
      RigPart.armRight => Transform.rotate(
        angle: -p.armRight,
        alignment: at,
        child: picture,
      ),
    };
  }

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: rig.canvas.aspectRatio,
    child: Semantics(
      label: semanticsLabel,
      image: semanticsLabel != null,
      child: ExcludeSemantics(
        child: Stack(
          fit: StackFit.expand,
          children: [
            SvgPicture.string(rig.body, fit: BoxFit.fill),
            for (final MapEntry(key: part, value: layer) in rig.layers.entries)
              _part(part, layer),
          ],
        ),
      ),
    ),
  );
}
