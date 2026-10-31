import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../data/art_source.dart';
import 'bogle_widgets.dart';
import 'home_return_route.dart';

/// From a friend's card in the archive into its house. The card opens: a
/// panel in the friend's colour grows from where the card was to fill the
/// screen, the house then appears through a circle widening from the
/// card's centre with bubbles (보글) rising off its edge, and the friend
/// hops from the card onto its rug (see [friendHeroShuttle]). Going back
/// plays it in reverse, into the card. Home closes in the same way, then
/// keeps shrinking until the panel and friend disappear completely.
Route<T> houseRoute<T>(
  Widget house, {
  required Rect from,
  required Color color,
}) => HomeReturnRoute<T>(
  transitionDuration: houseTransitionDuration,
  reverseTransitionDuration: const Duration(milliseconds: 800),
  homeTransitionDuration: const Duration(milliseconds: 900),
  pageBuilder: (_, _, _) => RepaintBoundary(child: house),
  transitionsBuilder: (context, animation, _, child) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final route = ModalRoute.of(context)! as HomeReturnRoute;
    return _CardOpening(
      animation: animation,
      from: from,
      color: color,
      disappear: route.returningHome,
      departure: route.returningHome ? route.departure : null,
      child: child,
    );
  },
);

const houseTransitionDuration = Duration(milliseconds: 1000);

class _CardOpening extends StatelessWidget {
  const _CardOpening({
    required this.animation,
    required this.from,
    required this.color,
    required this.child,
    this.disappear = false,
    this.departure,
  });
  final Animation<double> animation;
  final Rect from;
  final Color color;
  final Widget child;
  final bool disappear;
  final HomeDeparture? departure;

  /// The card grows over the first half; the house widens through the
  /// middle; the bubbles rise over the second two-thirds.
  static const _grow = Interval(0, .5, curve: Curves.easeInOutCubic);
  static const _reveal = Interval(.32, .88, curve: Curves.easeInOutCubic);
  static const _bubbles = Interval(.3, 1);
  static const _cover = Interval(0, .14, curve: Curves.easeOut);
  // The opening's reversal is unchanged until the final part. For Home,
  // carry the remaining panel past the card footprint all the way to zero.
  static const _vanish = Interval(0, .4, curve: Curves.easeInOutCubic);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final screen = Offset.zero & box.biggest;
      final centre = from.center;
      // Far enough to reach every corner.
      final reach = [
        screen.topLeft,
        screen.topRight,
        screen.bottomLeft,
        screen.bottomRight,
      ].map((c) => (c - centre).distance).reduce(math.max);
      return AnimatedBuilder(
        animation: animation,
        child: child,
        builder: (context, house) {
          final t = animation.value;
          final grow = _grow.transform(t);
          final reveal = _reveal.transform(t);
          final panel = Rect.lerp(from, screen, grow)!;
          final remaining = disappear ? _vanish.transform(t) : 1.0;
          return Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fromRect(
                rect: disappear
                    ? Rect.fromCenter(
                        center: panel.center,
                        width: panel.width * remaining,
                        height: panel.height * remaining,
                      )
                    : panel,
                child: IgnorePointer(
                  // Marks the Home closing without changing the tree above
                  // the house.
                  key: disappear ? const ValueKey('house-home-collapse') : null,
                  child: DecoratedBox(
                    key: disappear ? const ValueKey('house-home-panel') : null,
                    decoration: BoxDecoration(
                      // Fades in over the card as it starts to grow.
                      color: color.withValues(
                        alpha: _cover.transform(t) * color.a,
                      ),
                      borderRadius: BorderRadius.circular(6 * (1 - grow)),
                    ),
                  ),
                ),
              ),
              ClipPath(clipper: _Circle(centre, reach * reveal), child: house),
              IgnorePointer(
                child: CustomPaint(
                  painter: _Bubbles(
                    progress: _bubbles.transform(t),
                    centre: centre,
                    radius: reach * reveal,
                    tint: color,
                  ),
                ),
              ),
              if (departure case final departing?)
                _HomeDepartingFriend(
                  animation: animation,
                  departure: departing,
                  destination: centre,
                ),
            ],
          );
        },
      );
    },
  );
}

/// The friend follows the same direction as a return to its card, but
/// continues shrinking to nothing instead of handing off to an archive Hero.
class _HomeDepartingFriend extends StatelessWidget {
  const _HomeDepartingFriend({
    required this.animation,
    required this.departure,
    required this.destination,
  });
  final Animation<double> animation;
  final HomeDeparture departure;
  final Offset destination;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedBuilder(
      animation: animation,
      child: RepaintBoundary(child: departure.artwork),
      builder: (context, artwork) {
        final t = animation.value;
        final progress = Curves.easeInOutCubic.transform(1 - t);
        final start = departure.rect;
        return Opacity(
          opacity: const Interval(0, .16).transform(t),
          child: _AtGlobal(
            key: const ValueKey('house-home-friend'),
            drawingSize: start.size,
            rect: Rect.fromCenter(
              center: Offset.lerp(start.center, destination, progress)!,
              width: start.width * (1 - progress),
              height: start.height * (1 - progress),
            ),
            child: artwork!,
          ),
        );
      },
    ),
  );
}

class _Circle extends CustomClipper<Path> {
  _Circle(this.centre, this.radius);
  final Offset centre;
  final double radius;
  @override
  Path getClip(Size size) =>
      Path()..addOval(Rect.fromCircle(center: centre, radius: radius));
  @override
  bool shouldReclip(_Circle old) =>
      old.radius != radius || old.centre != centre;
}

/// Bubbles set off from the widening edge, rising and swaying as they
/// fade: soap-bubble rims with a glint, tinted with the friend's colour.
class _Bubbles extends CustomPainter {
  _Bubbles({
    required this.progress,
    required this.centre,
    required this.radius,
    required this.tint,
  });
  final double progress;
  final Offset centre;
  final double radius;
  final Color tint;

  static const _count = 16;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    final random = math.Random(7);
    for (var i = 0; i < _count; i++) {
      final angle = i / _count * math.pi * 2 + random.nextDouble() * .4;
      final start = random.nextDouble() * .45;
      final local = ((progress - start) / (1 - start)).clamp(0.0, 1.0);
      if (local <= 0) continue;
      final r = 7 + random.nextDouble() * 17;
      // Born on the edge as it passes, then rising with a little sway.
      final born = radius * (.55 + .4 * random.nextDouble());
      final rise = local * (90 + random.nextDouble() * 90);
      final sway = math.sin(local * math.pi * 2 + i) * 10;
      final at =
          centre +
          Offset(math.cos(angle), math.sin(angle)) * born +
          Offset(sway, -rise);
      final fade = math.sin(local * math.pi);
      canvas.drawCircle(
        at,
        r,
        Paint()..color = Colors.white.withValues(alpha: .18 * fade),
      );
      canvas.drawCircle(
        at,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Color.lerp(
            Colors.white,
            tint,
            .35,
          )!.withValues(alpha: .85 * fade),
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: at + Offset(-r * .35, -r * .4),
          width: r * .5,
          height: r * .28,
        ),
        Paint()..color = Colors.white.withValues(alpha: .8 * fade),
      );
    }
  }

  @override
  bool shouldRepaint(_Bubbles old) =>
      old.progress != progress || old.radius != radius;
}

/// A friend's hero between its archive card and its house: the same
/// drawing in both, framed as each frames it — centred in the card,
/// standing on the floor of its square in the house ([standing]).
///
/// It flies the way the startup wordmark settles into the corner: one
/// drawing, its centre gliding straight while it grows or shrinks at an
/// even rate, on a soft ease that sets off and settles without a lurch — no
/// hops or squashes, and both ends exactly where the drawing sits.
Widget friendHero({
  required String id,
  required String assetPath,
  required bool standing,
  required Widget child,
}) =>
    _FriendHero(id: id, assetPath: assetPath, standing: standing, child: child);

class _FriendHero extends StatefulWidget {
  const _FriendHero({
    required this.id,
    required this.assetPath,
    required this.standing,
    required this.child,
  });
  final String id, assetPath;
  final bool standing;
  final Widget child;

  @override
  State<_FriendHero> createState() => _FriendHeroState();
}

class _FriendHeroState extends State<_FriendHero> {
  // Flutter's default destination placeholder removes the figure entirely.
  // Keep it laid out offstage, with the same element tree on either side
  // of the handoff: layered SVGs/face images load during, not after, flight.
  final _drawing = GlobalKey();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (widget.standing && route is HomeReturnRoute) {
      route.captureDeparture = _captureDeparture;
    }
  }

  HomeDeparture? _captureDeparture() {
    final box = _drawing.currentContext?.findRenderObject() as RenderBox?;
    final rect = _InFlight._rect(box);
    if (rect == null) return null;
    final aspect = artAspects[widget.assetPath] ?? rect.size.aspectRatio;
    final size = rect.size.aspectRatio > aspect
        ? Size(rect.height * aspect, rect.height)
        : Size(rect.width, rect.width / aspect);
    return (
      rect: Alignment.bottomCenter.inscribe(size, rect),
      artwork: FriendArtwork(assetPath: widget.assetPath, fit: BoxFit.fill),
    );
  }

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context);
    final departing =
        widget.standing &&
        route is HomeReturnRoute &&
        route.returningHome &&
        route.departure != null;
    return Opacity(
      opacity: departing ? 0 : 1,
      child: Hero(
        tag: 'friend-${widget.id}',
        placeholderBuilder: (context, size, child) => SizedBox(
          width: size.width,
          height: size.height,
          child: Offstage(child: TickerMode(enabled: false, child: child)),
        ),
        flightShuttleBuilder: (context, animation, direction, from, to) =>
            _InFlight(
              animation: animation,
              into: direction == HeroFlightDirection.push,
              from: from,
              to: to,
              fromAlignment: widget.standing
                  ? Alignment.center
                  : Alignment.bottomCenter,
              toAlignment: widget.standing
                  ? Alignment.bottomCenter
                  : Alignment.center,
              assetPath: widget.assetPath,
            ),
        child: KeyedSubtree(key: _drawing, child: widget.child),
      ),
    );
  }
}

class _InFlight extends StatefulWidget {
  const _InFlight({
    required this.animation,
    required this.into,
    required this.from,
    required this.to,
    required this.fromAlignment,
    required this.toAlignment,
    required this.assetPath,
  });
  final Animation<double> animation;

  /// Into the house (opening the card) rather than back out to the card.
  final bool into;
  final BuildContext from, to;
  final Alignment fromAlignment, toAlignment;
  final String assetPath;

  /// The startup wordmark's ease (a soft sine).
  static const _glide = Cubic(.37, 0, .63, 1);

  /// Into the house it lands as the house opens round it; back out it
  /// leaves as the house folds and is home as the card closes.
  static const _intoHouse = Interval(.12, .9);
  static const _backToCard = Interval(.04, .94);

  /// Flutter runs a hero's flight on fastOutSlowIn; undo that to get the
  /// page's own (even) progress, so this flight keeps its own pace.
  static double _even(double eased) {
    var lo = 0.0, hi = 1.0;
    for (var i = 0; i < 18; i++) {
      final mid = (lo + hi) / 2;
      if (Curves.fastOutSlowIn.transform(mid) < eased) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return (lo + hi) / 2;
  }

  static Rect? _rect(RenderBox? box) {
    if (box == null || !box.attached || !box.hasSize || box.size.isEmpty) {
      return null;
    }
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  State<_InFlight> createState() => _InFlightState();
}

class _InFlightState extends State<_InFlight> {
  /// Where it set off, read once: in the house the friend keeps breathing
  /// and swaying, and following that would make it wobble on its way. Where
  /// it lands is followed to the end, so it lands exactly on it.
  Rect? _from;

  /// Where it lands, as last seen (that hero can leave the tree first).
  Rect? _to;

  /// The landing hero's box, taken while it is in the tree: its element can
  /// go inactive before the flight ends, its box then simply detaches.
  late final _landing = widget.to.findRenderObject() as RenderBox?;

  /// Where the drawing is in [box]: contained, at [alignment]. Until the
  /// drawing has been read, the house's figure, which is measured to the
  /// drawing, gives its shape ([standing]).
  Rect _drawing(Rect box, Alignment alignment, Rect standing) {
    final aspect = artAspects[widget.assetPath] ?? standing.size.aspectRatio;
    final size = box.size.aspectRatio > aspect
        ? Size(box.height * aspect, box.height)
        : Size(box.width, box.width / aspect);
    return alignment.inscribe(size, box);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.animation,
    child: RepaintBoundary(
      child: FriendArtwork(
        key: const ValueKey('friend-in-flight'),
        assetPath: widget.assetPath,
        fit: BoxFit.fill,
      ),
    ),
    builder: (context, artwork) {
      final a = _from ??= _InFlight._rect(
        widget.from.findRenderObject() as RenderBox?,
      );
      final b = _to = _InFlight._rect(_landing) ?? _to;
      if (a == null || b == null) return const SizedBox();
      final standing = widget.toAlignment == Alignment.bottomCenter ? b : a;
      final start = _drawing(a, widget.fromAlignment, standing);
      final end = _drawing(b, widget.toAlignment, standing);
      // A push's flight runs 0 → 1, a pop's 1 → 0; either way this is how
      // far it has come from where it set off.
      final value = widget.animation.value;
      final t = _InFlight._glide.transform(
        (widget.into ? _InFlight._intoHouse : _InFlight._backToCard).transform(
          _InFlight._even(widget.into ? value : 1 - value),
        ),
      );
      final scale = math.pow(end.width / start.width, t).toDouble();
      final centre = Offset.lerp(start.center, end.center, t)!;
      return _AtGlobal(
        drawingSize: end.size,
        rect: Rect.fromCenter(
          center: centre,
          width: start.width * scale,
          height: start.height * scale,
        ),
        child: artwork!,
      );
    },
  );
}

/// Paints [child] at [rect] on the screen, wherever Flutter has put the
/// shuttle (which follows the heroes' boxes, not the drawing).
class _AtGlobal extends SingleChildRenderObjectWidget {
  const _AtGlobal({
    super.key,
    required this.rect,
    required this.drawingSize,
    required super.child,
  });
  final Rect rect;
  final Size drawingSize;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderAtGlobal(rect, drawingSize);
  @override
  void updateRenderObject(BuildContext context, _RenderAtGlobal r) => r
    ..drawingSize = drawingSize
    ..rect = rect;
}

class _RenderAtGlobal extends RenderProxyBox {
  _RenderAtGlobal(this._rect, this._drawingSize);
  Rect _rect;
  Size _drawingSize;
  set drawingSize(Size value) {
    if (value == _drawingSize) return;
    _drawingSize = value;
    markNeedsLayout();
  }

  set rect(Rect value) {
    if (value == _rect) return;
    _rect = value;
    markNeedsPaint();
  }

  @override
  void performLayout() {
    // Layout/decode the artwork once at its destination size. The flight
    // only changes a paint transform, not the SVG/image's layout each frame.
    child?.layout(BoxConstraints.tight(_drawingSize));
    size = constraints.biggest;
  }

  Offset get _shift => _rect.topLeft - localToGlobal(Offset.zero);

  Matrix4 get _transform {
    final shift = _shift;
    return Matrix4.identity()
      ..translateByDouble(shift.dx, shift.dy, 0, 1)
      ..scaleByDouble(
        _rect.width / _drawingSize.width,
        _rect.height / _drawingSize.height,
        1,
        1,
      );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child != null) {
      context.pushTransform(
        needsCompositing,
        offset,
        _transform,
        (context, offset) => context.paintChild(child, offset),
      );
    }
  }

  @override
  void applyPaintTransform(RenderObject child, Matrix4 transform) {
    transform.multiply(_transform);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      false;
}
