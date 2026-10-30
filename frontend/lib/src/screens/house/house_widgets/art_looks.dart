part of '../house_widgets.dart';

// What a friend's artwork looks like: where its head and mouth are, how much of
// it is drawn, whether it stands as a card, and measuring a drawn figure.

/// Where a friend's face is, for holding a snack to its mouth and putting
/// its speech balloon by its head. All rects are fractions of the drawn
/// figure's box.
class FigureAnchors {
  const FigureAnchors({required this.head, this.mouth, this.facing = 0});

  /// The head, or the whole drawing when it's all head (뭉글이).
  final Rect head;
  final Rect? mouth;

  /// -1 looking left, 1 right, 0 straight at us.
  final double facing;

  static const whole = FigureAnchors(head: Rect.fromLTWH(0, 0, 1, 1));
}

final _anchors = ArtCache<String, Future<FigureAnchors>>(96);

/// From the drawing's rig or face map when it has one; otherwise the drawn
/// part stands for the head and the mouth is left to a guess.
Future<FigureAnchors> anchorsFor(String assetPath) =>
    _anchors['$assetPath#${faceMapRevision(assetPath)}'] ??= () async {
      final art = await artBounds(assetPath);
      if (await standsAsCard(assetPath)) return FigureAnchors(head: art);
      final rig = await rigFor(assetPath);
      if (rig != null) {
        return FigureAnchors(
          head: art,
          mouth: rig.layers[RigPart.mouth]?.bounds,
          facing: rig.facing,
        );
      }
      final face = await faceMapFor(assetPath);
      if (face != null) {
        return FigureAnchors(
          head: face.head == null ? art : face.fraction(face.head!),
          mouth: face.mouth == null ? null : face.fraction(face.mouth!),
          facing: face.facing,
        );
      }
      return FigureAnchors(head: art);
    }();

/// The part of a friend's artwork box that is actually drawn, as fractions
/// of that box. Vector friends rarely fill their canvas, so the bubble
/// measures the head instead of guessing from the box. Art standing as a
/// card (see [standsAsCard]) is drawn all over.
Future<Rect> artBounds(String assetPath) async {
  const full = Rect.fromLTWH(0, 0, 1, 1);
  if (isPhotographedArt(assetPath)) return full;
  final look = await artLookOf(assetPath);
  if (look == null || !look.clearGround) return full;
  return look.drawn;
}

/// Whether a friend's artwork has a background of its own — a photographed
/// drawing, or a picture that came with one — and so stands in the room
/// as a card rather than as a cut-out. Unreadable art shows the new-friend
/// drawing instead (see [FriendArtwork.missing]), which is cut out.
Future<bool> standsAsCard(String assetPath) async {
  if (isPhotographedArt(assetPath)) return true;
  final look = await artLookOf(assetPath);
  return look != null && !look.clearGround;
}

/// What a friend's artwork is like, read once: its own size, the part of it
/// that is drawn, and whether its ground is clear (cut-out art) or painted
/// (a photo, or a picture with a background). Null when it can't be read.
///
/// [body] is where its body is, as the eye weighs it: the middle of what
/// is left once thin parts — a tail, antennae, whiskers, a giraffe's neck
/// tip — are worn away. [fill] is how much of the artwork box is drawn on.
/// Both are fractions of the box; they let a card size and centre the
/// friend by how it looks rather than by its box (see [cardFigureRect]).
/// [colors] are the colours it is painted in, each with its share of the
/// painted area, most first (see [cardColorFor]).
typedef ArtLook = ({
  Size natural,
  Rect drawn,
  bool clearGround,
  Offset body,
  double fill,
  List<(Color, double)> colors,
});

Future<ArtLook?> artLookOf(String assetPath) =>
    _looks[assetPath] ??= _readLook(assetPath).then((look) {
      _measured[assetPath] = look;
      return look;
    });

final _looks = ArtCache<String, Future<ArtLook?>>(64);
final _measured = ArtCache<String, ArtLook?>(64);

/// The artwork's look if it has been read already, for laying out its
/// first frame without waiting; null when it hasn't (or can't be).
ArtLook? measuredArtLook(String assetPath) => _measured[assetPath];

/// Measured on a small copy: solid paint (soft shadows and glows left out)
/// is what is drawn, and the ground is clear when at least three of the
/// four corners are.
Future<ArtLook?> _readLook(String assetPath) async {
  try {
    final ui.Image image;
    final Size natural;
    if (isSvgArt(assetPath)) {
      final info = await vg.loadPicture(artSvgLoader(assetPath), null);
      natural = info.size;
      final scale = 160 / math.max(info.size.width, info.size.height);
      final recorder = ui.PictureRecorder();
      Canvas(recorder)
        ..scale(scale)
        ..drawPicture(info.picture);
      final picture = recorder.endRecording();
      image = await picture.toImage(
        (info.size.width * scale).ceil(),
        (info.size.height * scale).ceil(),
      );
      picture.dispose();
      info.picture.dispose();
    } else {
      final bytes = await loadArtBytes(assetPath);
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      natural = Size(descriptor.width.toDouble(), descriptor.height.toDouble());
      descriptor.dispose();
      buffer.dispose();
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 160);
      image = (await codec.getNextFrame()).image;
      codec.dispose();
    }
    final w = image.width, h = image.height;
    final pixels = await image.toByteData();
    image.dispose();
    if (pixels == null || w == 0 || h == 0) return null;
    bool solid(int x, int y) => pixels.getUint8((y * w + x) * 4 + 3) >= 110;
    final clearCorners = [
      (0, 0),
      (w - 1, 0),
      (0, h - 1),
      (w - 1, h - 1),
    ].where((c) => !solid(c.$1, c.$2)).length;
    var left = w, top = h, right = -1, bottom = -1;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (!solid(x, y)) continue;
        left = math.min(left, x);
        right = math.max(right, x);
        top = math.min(top, y);
        bottom = math.max(bottom, y);
      }
    }
    artAspects[assetPath] = natural.aspectRatio;
    final (body, solidCount) = right < 0
        ? (const Offset(.5, .5), 0)
        : _bodyCentre(
            [for (var i = 0; i < w * h; i++) solid(i % w, i ~/ w)],
            w,
            h,
            wear: math.max(2, .05 * math.max(right - left, bottom - top)),
          );
    return (
      natural: natural,
      drawn: right < 0
          ? const Rect.fromLTWH(0, 0, 1, 1)
          : Rect.fromLTRB(left / w, top / h, (right + 1) / w, (bottom + 1) / h),
      body: body,
      fill: solidCount / (w * h),
      colors: _paintColours(pixels, w, h),
      // A picture cut to its figure had a clear ground, though its new
      // corners may land on the figure.
      clearGround: clearCorners >= 3 || await artCropOf(assetPath) != null,
    );
  } catch (_) {
    return null;
  }
}

/// The middle of a drawing's body (as fractions of its box) and how many
/// pixels are drawn. Every pixel is given its distance from the edge of the
/// drawing; parts thinner than twice [wear] (tails, antennae, whiskers)
/// never get that far in, so the middle of the rest is the body's. A drawing
/// that is thin all over keeps all of it.
(Offset, int) _bodyCentre(
  List<bool> solid,
  int w,
  int h, {
  required double wear,
}) {
  const far = 1 << 20;
  // Chamfer distance (3–4), two passes; 3 is one pixel.
  final d = List<int>.filled(w * h, 0);
  for (var i = 0; i < w * h; i++) {
    d[i] = solid[i] ? far : 0;
  }
  int at(int x, int y) => x < 0 || y < 0 || x >= w || y >= h ? 0 : d[y * w + x];
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      if (d[i] == 0) continue;
      d[i] = [
        d[i],
        at(x - 1, y) + 3,
        at(x, y - 1) + 3,
        at(x - 1, y - 1) + 4,
        at(x + 1, y - 1) + 4,
      ].reduce(math.min);
    }
  }
  for (var y = h - 1; y >= 0; y--) {
    for (var x = w - 1; x >= 0; x--) {
      final i = y * w + x;
      if (d[i] == 0) continue;
      d[i] = [
        d[i],
        at(x + 1, y) + 3,
        at(x, y + 1) + 3,
        at(x + 1, y + 1) + 4,
        at(x - 1, y + 1) + 4,
      ].reduce(math.min);
    }
  }
  (Offset, int) centre(int deep) {
    var n = 0;
    var sx = 0.0, sy = 0.0;
    for (var i = 0; i < w * h; i++) {
      if (d[i] < deep) continue;
      n++;
      sx += i % w + .5;
      sy += i ~/ w + .5;
    }
    return (n == 0 ? const Offset(.5, .5) : Offset(sx / n / w, sy / n / h), n);
  }

  final (_, drawn) = centre(1);
  final (core, kept) = centre((wear * 3).ceil());
  // Worn away to almost nothing: weigh the whole drawing.
  return (kept * 20 < drawn ? centre(1).$1 : core, drawn);
}

/// The colours a drawing is painted in (solid pixels only, close shades as
/// one), each with its share of the painted area, most first; enough of
/// them to cover nearly all of it.
List<(Color, double)> _paintColours(ByteData pixels, int w, int h) {
  final sums = <int, (int, int, int, int)>{};
  var total = 0;
  for (var i = 0; i < w * h; i++) {
    if (pixels.getUint8(i * 4 + 3) < 200) continue;
    final r = pixels.getUint8(i * 4),
        g = pixels.getUint8(i * 4 + 1),
        b = pixels.getUint8(i * 4 + 2);
    final key = (r >> 3) << 10 | (g >> 3) << 5 | b >> 3;
    final (n, sr, sg, sb) = sums[key] ?? (0, 0, 0, 0);
    sums[key] = (n + 1, sr + r, sg + g, sb + b);
    total++;
  }
  if (total == 0) return const [];
  final bins = sums.values.toList()..sort((a, b) => b.$1.compareTo(a.$1));
  final colours = <(Color, double)>[];
  var covered = 0;
  for (final (n, r, g, b) in bins) {
    colours.add((Color.fromARGB(255, r ~/ n, g ~/ n, b ~/ n), n / total));
    covered += n;
    if (covered >= total * .995 || colours.length == 48) break;
  }
  return colours;
}

/// How different two colours must look (CIELAB ΔE) for a friend to stand
/// out from its card.
const cardColorApart = 20.0;

/// How much of a friend's painted area must stand out from its card.
const cardColorCover = .9;

/// The card's dark name and introduction need this contrast (WCAG AA for
/// small text).
const cardTextContrast = 4.5;

/// The colour of a friend's archive card. The friend's own colour [accent]
/// (its dolls, chat and invites use it too) when the friend stands out on
/// it and the card's dark writing reads on it — true of the friends the app
/// ships with. When the friend would melt into it, as a one-colour friend
/// does on its average colour, the same colour is made lighter (or, for a
/// pale friend, deeper) only as far as it takes; out of reach, the shade
/// that sets most of the friend apart.
Color cardColorFor(Color accent, ArtLook? look) {
  if (look == null || !look.clearGround || look.colors.isEmpty) return accent;
  final paint = [for (final (c, share) in look.colors) (_lab(c), share)];
  double apart(Color card) {
    final lab = _lab(card);
    var share = 0.0;
    for (final (c, s) in paint) {
      if (_deltaE(lab, c) >= cardColorApart) share += s;
    }
    return share;
  }

  bool readable(Color card) =>
      _contrast(card, BogleColors.text) >= cardTextContrast;
  final hsl = HSLColor.fromColor(accent);
  final shades = [
    accent,
    for (var i = 1; i <= 19; i++) Color.lerp(accent, Colors.white, i * .05)!,
    for (var i = 1; i <= 14; i++)
      hsl
          .withLightness(math.max(0, hsl.lightness - i * .04))
          .withSaturation(math.min(1, hsl.saturation + i * .01))
          .toColor(),
  ].where(readable).toList();
  if (shades.isEmpty) return accent;
  final own = _lab(accent);
  double change(Color c) => _deltaE(_lab(c), own);
  final enough = shades.where((c) => apart(c) >= cardColorCover).toList();
  if (enough.isNotEmpty) {
    return enough.reduce((a, b) => change(b) < change(a) ? b : a);
  }
  return shades.reduce((a, b) {
    final da = apart(a), db = apart(b);
    return db > da || (db == da && change(b) < change(a)) ? b : a;
  });
}

/// The colour of [friend]'s archive card (see [cardColorFor]).
Color friendCardColor(CharacterFriend friend, ArtLook? look) =>
    cardColorFor(Color(friend.accentHex), look);

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + .05) / (math.min(la, lb) + .05);
}

/// CIELAB (D65) of an sRGB colour.
(double, double, double) _lab(Color c) {
  double lin(double v) =>
      v <= .04045 ? v / 12.92 : math.pow((v + .055) / 1.055, 2.4).toDouble();
  final r = lin(c.r), g = lin(c.g), b = lin(c.b);
  final x = (r * .4124 + g * .3576 + b * .1805) / .95047;
  final y = r * .2126 + g * .7152 + b * .0722;
  final z = (r * .0193 + g * .1192 + b * .9505) / 1.08883;
  double f(double t) =>
      t > .008856 ? math.pow(t, 1 / 3).toDouble() : 7.787 * t + 16 / 116;
  final fx = f(x), fy = f(y), fz = f(z);
  return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz));
}

double _deltaE((double, double, double) a, (double, double, double) b) {
  final dl = a.$1 - b.$1, da = a.$2 - b.$2, db = a.$3 - b.$3;
  return math.sqrt(dl * dl + da * da + db * db);
}

/// How big a friend looks on its archive card, as the share of the card's
/// picture width squared that its drawn pixels cover — reached only partway
/// (see [cardFigureEvenness]). Chosen so 뭉글이 keeps the size the card was
/// designed with; a plump friend filling its box would look far heavier.
const cardFigureFill = .17;

/// How far a card goes toward [cardFigureFill] for a friend that would
/// cover more: 0 fills the box as before, 1 makes every drawn area equal.
/// All the way makes a plump friend look smaller than a slim one, since a
/// solid shape reads as small for its area; partway, the cards weigh alike.
const cardFigureEvenness = .6;

/// Where on a card's picture the middle of a friend's drawing sits, from
/// the top: a touch below centre, so it sits rather than floats.
const cardFigureMiddle = .52;

/// Where a friend's artwork goes in a card's picture [slot] of this [look]:
/// sized by how much of it is drawn rather than by its box (see
/// [cardFigureFill]), never larger than fits; its drawing a touch below the
/// middle, and moved sideways so its body — not a tail or an antenna — is
/// in the middle, keeping every drawn pixel inside. Art with a ground of its
/// own (a photographed drawing) is fitted whole and centred as before.
Rect cardFigureRect(Size slot, ArtLook look) {
  final aspect = look.natural.aspectRatio;
  final drawn = look.drawn;
  Rect contain() {
    final width = math.min(slot.width, slot.height * aspect);
    return Alignment.center.inscribe(
      Size(width, width / aspect),
      Offset.zero & slot,
    );
  }

  if (!look.clearGround || drawn.isEmpty || look.fill <= 0) return contain();
  // The artwork box's width when its drawing just fits the slot, and when
  // the drawing covers its share of the slot.
  final fits = math.min(
    slot.width / drawn.width,
    slot.height * aspect / drawn.height,
  );
  final looks = math.sqrt(
    cardFigureFill * slot.width * slot.width * aspect / look.fill,
  );
  final width = fits * math.pow(math.min(1, looks / fits), cardFigureEvenness);
  final height = width / aspect;
  final left = (slot.width / 2 - look.body.dx * width).clamp(
    -drawn.left * width,
    slot.width - drawn.right * width,
  );
  final top = (slot.height * cardFigureMiddle - drawn.center.dy * height).clamp(
    -drawn.top * height,
    slot.height - drawn.bottom * height,
  );
  return Rect.fromLTWH(left, top, width, height);
}

/// A friend's artwork laid out on its archive card (see [cardFigureRect]).
/// [child] is the artwork, given exactly the box it should fill — so a hero
/// flying from here leaves from where the drawing is. Until the artwork has
/// been measured it waits, unseen, rather than show in one place and jump
/// to another.
class CardFigure extends StatefulWidget {
  const CardFigure({super.key, required this.assetPath, required this.child});
  final String assetPath;
  final Widget child;

  @override
  State<CardFigure> createState() => _CardFigureState();
}

class _CardFigureState extends State<CardFigure> {
  late ArtLook? _look = measuredArtLook(widget.assetPath);
  late bool _read = _look != null;

  @override
  void initState() {
    super.initState();
    if (!_read) _measure();
  }

  @override
  void didUpdateWidget(CardFigure old) {
    super.didUpdateWidget(old);
    if (old.assetPath != widget.assetPath) {
      _look = measuredArtLook(widget.assetPath);
      _read = _look != null;
      if (!_read) _measure();
    }
  }

  void _measure() {
    final path = widget.assetPath;
    artLookOf(path).then((look) {
      if (!mounted || widget.assetPath != path) return;
      setState(() {
        _look = look;
        _read = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, slot) {
      final size = slot.biggest;
      final look = _look;
      if (look == null) {
        // Not measured yet (unseen), or unreadable (the stand-in drawing,
        // fitted as it always was).
        return Opacity(
          opacity: _read ? 1 : 0,
          child: Center(child: widget.child),
        );
      }
      final rect = cardFigureRect(size, look);
      return Stack(
        clipBehavior: Clip.none,
        children: [Positioned.fromRect(rect: rect, child: widget.child)],
      );
    },
  );
}

/// Reports its child's laid-out size. Paint transforms (breathing, jumps)
/// don't change it, so the bubble stays put while the friend moves.
class _MeasureSize extends SingleChildRenderObjectWidget {
  const _MeasureSize({required this.onSize, required super.child});
  final ValueChanged<Size>? onSize;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasureSize(onSize);
  @override
  void updateRenderObject(BuildContext context, _RenderMeasureSize r) =>
      r.onSize = onSize;
}

class _RenderMeasureSize extends RenderProxyBox {
  _RenderMeasureSize(this.onSize);
  ValueChanged<Size>? onSize;
  Size? _last;
  @override
  void performLayout() {
    super.performLayout();
    if (size == _last) return;
    final s = _last = size;
    WidgetsBinding.instance.addPostFrameCallback((_) => onSize?.call(s));
  }
}
