import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/bogle_theme.dart';
import 'ribbon_motion.dart';
import '../app_lifecycle.dart';

enum FireworksStyle { handHeld, screenFan }

enum _PaintLayer { all, behind, front }

/// Birthday-party cones followed by long, gently drifting streamers.
/// A decorative overlay; never loops or consumes input.
/// The previous multi-burst design remains in classic_fireworks.dart.
class Fireworks extends StatefulWidget {
  const Fireworks({
    super.key,
    this.seed = 7,
    this.style = FireworksStyle.handHeld,
    this.handTarget,
    this.handFraction,
    this.child,
    this.active = true,
    this.focusTarget,
    this.keepClear,
  });

  static const duration = Duration(milliseconds: 11500);
  final int seed;
  final FireworksStyle style;

  /// Content placed between rising and falling ribbons, sharing one clock.
  final Widget? child;
  final bool active;

  /// An artwork render box and its normalized, asset-specific grip point.
  /// Unmapped drawings keep the standalone cone rather than guessing a hand.
  final GlobalKey? handTarget;
  final Offset? handFraction;

  /// Screen-fan only: the character the two bouquets cross behind. Each
  /// ribbon flies through a spot behind it, then fans out above it, so the
  /// crossing and every turn are hidden. Without it they cross in the open.
  final GlobalKey? focusTarget;

  /// Screen-fan only: controls the two cannons must not cover, such as a
  /// row of buttons along the bottom. Where the usual spot would overlap
  /// them, each cannon moves out beside them.
  final GlobalKey? keepClear;

  @override
  State<Fireworks> createState() => _FireworksState();
}

class _FireworksState extends State<Fireworks>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller;
  late final List<_Streamer> _streamers;
  bool _still = false;
  bool _foreground = true;

  ({Offset grip, double unit})? _attachment() {
    final fraction = widget.handFraction;
    final target = widget.handTarget?.currentContext?.findRenderObject();
    final surface = context.findRenderObject();
    if (fraction == null ||
        target is! RenderBox ||
        surface is! RenderBox ||
        !target.attached ||
        !surface.attached ||
        !target.hasSize ||
        !surface.hasSize) {
      return null;
    }
    final global = target.localToGlobal(
      Offset(target.size.width * fraction.dx, target.size.height * fraction.dy),
    );
    return (
      grip: surface.globalToLocal(global),
      unit: target.size.height * 4.2,
    );
  }

  /// Where [Fireworks.focusTarget] is, in this widget's coordinates.
  Rect? _focus() => _rectOf(widget.focusTarget);

  /// Where [Fireworks.keepClear] is, in this widget's coordinates.
  Rect? _clear() => _rectOf(widget.keepClear);

  Rect? _rectOf(GlobalKey? key) {
    final target = key?.currentContext?.findRenderObject();
    final surface = context.findRenderObject();
    if (target is! RenderBox ||
        surface is! RenderBox ||
        !target.attached ||
        !surface.attached ||
        !target.hasSize ||
        !surface.hasSize) {
      return null;
    }
    final topLeft = surface.globalToLocal(target.localToGlobal(Offset.zero));
    return topLeft & target.size;
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Fireworks.duration,
    );
    _streamers = _Streamer.plan(widget.seed, widget.style);
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = onScreen(state);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.disableAnimationsOf(context);
    _syncPlayback();
  }

  void _syncPlayback() {
    if (!widget.active) {
      _controller.stop();
    } else if (_still) {
      _controller.stop();
      _controller.value = 1;
    } else if (_foreground && TickerMode.valuesOf(context).enabled) {
      if (!_controller.isAnimating && !_controller.isCompleted) {
        _controller.forward();
      }
    } else {
      _controller.stop();
    }
  }

  @override
  void didUpdateWidget(Fireworks oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.active && widget.active) _controller.value = 0;
    _syncPlayback();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = onScreen(state);
    _syncPlayback();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible = !_still && widget.active;
    if (widget.child == null) {
      return visible ? _decoration(_PaintLayer.all) : const SizedBox.expand();
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        if (visible) Positioned.fill(child: _decoration(_PaintLayer.behind)),
        KeyedSubtree(
          key: const ValueKey('fireworks-content'),
          child: widget.child!,
        ),
        if (visible) Positioned.fill(child: _decoration(_PaintLayer.front)),
      ],
    );
  }

  Widget _decoration(_PaintLayer layer) => IgnorePointer(
    child: ExcludeSemantics(
      child: RepaintBoundary(
        key: ValueKey(
          layer == _PaintLayer.behind
              ? 'fireworks-behind-canvas'
              : 'fireworks-canvas',
        ),
        child: CustomPaint(
          size: Size.infinite,
          painter: _BirthdayPainter(
            _controller,
            _streamers,
            _attachment,
            widget.style,
            layer,
            _focus,
            _clear,
          ),
        ),
      ),
    ),
  );
}

const _colors = [
  BogleColors.logo,
  Color(0xFFF590AD),
  Color(0xFF65C9AB),
  Color(0xFFEAB74E),
  Color(0xFFB298E6),
  Color(0xFF7DC7EB),
];

class _Streamer {
  const _Streamer({
    required this.x,
    required this.y,
    required this.flight,
    required this.fall,
    required this.length,
    required this.width,
    required this.phase,
    required this.curls,
    required this.color,
  });

  final double x, y, flight, fall, length, width, phase, curls;
  final Color color;

  static List<_Streamer> plan(int seed, FireworksStyle style) {
    final random = math.Random(seed);
    if (style == FireworksStyle.screenFan) {
      // Two compact side cannons, with varied arcs rather than a rigid fan.
      return [
        for (var i = 0; i < 16; i++)
          for (final side in [-1, 1])
            _Streamer(
              x: .5 + side * (.13 + .32 * i / 15),
              y: .09 + random.nextDouble() * .18,
              flight: 1.3 + random.nextDouble() * .40,
              fall: 6.0 + random.nextDouble() * .60,
              length: .18 + random.nextDouble() * .09,
              width: 3.0 + random.nextDouble() * 1.7,
              phase: random.nextDouble() * math.pi * 2,
              curls: .65 + random.nextDouble() * 1.1,
              color: _colors[(i + (side > 0 ? 2 : 0)) % _colors.length],
            ),
      ];
    }
    return List.generate(
      30,
      (i) => _Streamer(
        // Evenly spread with slight variation, not a dense central curtain.
        x: .035 + .93 * (i + random.nextDouble() * .6) / 30,
        y: .015 + random.nextDouble() * .10,
        flight: .95 + random.nextDouble() * .40,
        fall: 6.2 + random.nextDouble() * .95,
        length: .12 + random.nextDouble() * .15,
        width: 2.8 + random.nextDouble() * 2.0,
        phase: random.nextDouble() * math.pi * 2,
        curls: .65 + random.nextDouble() * 1.1,
        color: _colors[i % _colors.length],
      ),
    );
  }
}

class _BirthdayPainter extends CustomPainter {
  _BirthdayPainter(
    this.progress,
    this.streamers,
    this.attachment,
    this.style,
    this.layer,
    this.focus,
    this.clear,
  ) : super(repaint: progress);
  final Animation<double> progress;
  final List<_Streamer> streamers;
  final ({Offset grip, double unit})? Function() attachment;
  final FireworksStyle style;
  final _PaintLayer layer;
  final Rect? Function() focus;
  final Rect? Function() clear;
  static const _popAt = .85;

  /// The right cannon fires this much later, so the two bouquets pass the
  /// crossing one after the other instead of meshing.
  static const _secondCannon = .35;

  static double _smooth(double t) {
    final x = t.clamp(0.0, 1.0);
    return x * x * (3 - 2 * x);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final seconds = progress.value * Fireworks.duration.inMilliseconds / 1000;
    if (seconds <= 0 || progress.value >= 1) return;
    final age = seconds - _popAt;
    if (style == FireworksStyle.screenFan) {
      final unit = size.shortestSide;
      final keepClear = clear();
      canvas.save();
      canvas.clipRect(Offset.zero & size);
      for (final side in [-1, 1]) {
        final localSeconds = seconds - (side == 1 ? _secondCannon : 0);
        final localAge = localSeconds - _popAt;
        final enter = Curves.easeOutCubic.transform(
          ((localSeconds - .08) / .50).clamp(0.0, 1.0),
        );
        final recoilAge = math.max(0.0, localAge);
        final recoil = recoilAge < .45
            ? math.sin(recoilAge / .45 * math.pi) * math.exp(-recoilAge * 5)
            : 0.0;
        final angle = -side * (.58 - recoil * .08);
        final scale = (.86 + .14 * enter) * (1 - recoil * .08);
        // Less than half the previous cone's linear size. Both tips remain
        // inside the viewport and leave the central action buttons visible.
        final coneUnit = unit * 1.05;
        // Leaning inward, a cone reaches about .09 of its unit past its
        // tip; keep that clear of [keepClear] with a small margin.
        var tipX = size.width * (.5 + side * .34);
        if (keepClear != null) {
          final reach = coneUnit * .09 + 24;
          tipX = side < 0
              ? math.min(tipX, keepClear.left - reach)
              : math.max(tipX, keepClear.right + reach);
        }
        final tip = Offset(tipX, size.height - unit * .035);
        final origin =
            tip -
            Offset(-math.sin(angle), math.cos(angle)) *
                coneUnit *
                .105 *
                .90 *
                scale;
        if (localAge > 0) {
          if (layer != _PaintLayer.front) {
            _screenPop(canvas, origin, unit, localAge, angle);
          }
          for (final ribbon in streamers) {
            // Left cannon sends its bouquet up and right, and vice versa.
            if ((ribbon.x > .5) == (side < 0)) {
              final front = _smooth((localAge - ribbon.flight) / .20);
              final weight = switch (layer) {
                _PaintLayer.all => 1.0,
                _PaintLayer.behind => 1 - front,
                _PaintLayer.front => front,
              };
              if (weight > 0) {
                _ribbon(
                  canvas,
                  size,
                  origin,
                  ribbon,
                  localAge,
                  weight: weight,
                  focus: focus(),
                );
              }
            }
          }
        }
        if (layer != _PaintLayer.behind) {
          _cone(canvas, origin, coneUnit, localSeconds, angle, scale);
        }
      }
      canvas.restore();
      return;
    }
    if (layer == _PaintLayer.behind) return;
    final held = attachment();
    final coneUnit = held?.unit ?? size.shortestSide;
    final enter = Curves.easeOutCubic.transform(
      ((seconds - .08) / .50).clamp(0.0, 1.0),
    );
    final recoilAge = math.max(0.0, age);
    final recoil = recoilAge < .55
        ? math.sin(recoilAge / .55 * math.pi) * math.exp(-recoilAge * 4)
        : 0.0;
    final angle = .52 + recoil * .065;
    final scale = .86 + .14 * enter;
    final gripDistance = coneUnit * .105 * .90 * scale;
    // Rotate/scale around the hand, never around the opening: the grip remains
    // attached even during the pop. Use this exact mouth for ribbon emission.
    final mouth = held == null
        ? Offset(size.width * .5, size.height * .175)
        : held.grip - Offset(-math.sin(angle), math.cos(angle)) * gripDistance;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    if (age > 0) {
      _pop(canvas, mouth, size.shortestSide, age);
      for (final ribbon in streamers) {
        _ribbon(canvas, size, mouth, ribbon, age);
      }
    }
    _cone(canvas, mouth, coneUnit, seconds, angle, scale);
    canvas.restore();
  }

  /// Original vector artwork: striped paper cone with an open elliptical rim.
  /// Its opening is the same origin used by every emitted strand.
  void _cone(
    Canvas canvas,
    Offset mouth,
    double unit,
    double seconds,
    double angle,
    double scale,
  ) {
    final enter = Curves.easeOutCubic.transform(
      ((seconds - .08) / .50).clamp(0.0, 1.0),
    );
    final fade = 1 - _smooth((seconds - 2.0) / .65);
    if (enter == 0 || fade == 0) return;
    final width = unit * .09;
    final length = unit * .105;
    canvas.save();
    canvas.translate(mouth.dx, mouth.dy);
    canvas.rotate(angle);
    canvas.scale(scale);
    Color tint(Color c) => c.withValues(alpha: enter * fade);
    final body = Path()
      ..moveTo(-width / 2, 0)
      ..quadraticBezierTo(
        -width * .29,
        length * .53,
        -width * .04,
        length * .97,
      )
      ..quadraticBezierTo(0, length * 1.03, width * .04, length * .97)
      ..quadraticBezierTo(width * .29, length * .53, width / 2, 0)
      ..close();
    canvas.drawPath(
      body.shift(const Offset(1.5, 2)),
      Paint()..color = tint(const Color(0x123A4A8C)),
    );
    canvas.drawPath(
      body,
      Paint()
        ..shader = LinearGradient(
          colors: [
            tint(const Color(0xFFFFD77B)),
            tint(const Color(0xFFF2B748)),
            tint(const Color(0xFFE5A333)),
          ],
        ).createShader(Rect.fromLTWH(-width / 2, 0, width, length)),
    );
    canvas.save();
    canvas.clipPath(body);
    final stripe = Paint()
      ..color = tint(const Color(0xFF72BCAA))
      ..style = PaintingStyle.stroke
      ..strokeWidth = width * .16;
    for (var i = -2; i < 7; i++) {
      final y = i * length * .23;
      canvas.drawLine(
        Offset(-width, y),
        Offset(width, y + length * .36),
        stripe,
      );
    }
    canvas.restore();
    final rim = Rect.fromCenter(
      center: Offset.zero,
      width: width,
      height: width * .25,
    );
    canvas.drawOval(rim, Paint()..color = tint(const Color(0xFFB87E27)));
    canvas.drawOval(
      rim.deflate(width * .035),
      Paint()..color = tint(const Color(0xFFD89934)),
    );
    canvas.drawArc(
      rim,
      0,
      math.pi,
      false,
      Paint()
        ..color = tint(const Color(0xFFFFDF8F))
        ..style = PaintingStyle.stroke
        ..strokeWidth = width * .055
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();
  }

  /// A brief, directional mouth sparkle, not a second explosion in mid-air.
  void _screenPop(
    Canvas canvas,
    Offset origin,
    double unit,
    double age,
    double coneAngle,
  ) {
    if (age > .5) return;
    final t = age / .5;
    for (var i = 0; i < 9; i++) {
      final angle = -math.pi / 2 + coneAngle + (i / 8 - .5) * .9;
      final direction = Offset(math.cos(angle), math.sin(angle));
      final head =
          origin + direction * unit * .18 * Curves.easeOutCubic.transform(t);
      canvas.drawLine(
        head - direction * unit * .025 * (1 - t),
        head,
        Paint()
          ..color = _colors[i % _colors.length].withValues(alpha: 1 - t)
          ..strokeWidth = 2.5 * (1 - t) + 1
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  /// A single upward fan from the mouth, not an unrelated circular explosion.
  void _pop(Canvas canvas, Offset mouth, double unit, double age) {
    if (age > .85) return;
    final t = age / .85;
    final reach = Curves.easeOutCubic.transform(t) * unit * .31;
    final opacity = math.pow(1 - t, 1.6).toDouble();
    for (var i = 0; i < 23; i++) {
      final angle = -math.pi + .17 + i / 22 * (math.pi - .34);
      final direction = Offset(math.cos(angle), math.sin(angle));
      final head = mouth + direction * reach * (i.isEven ? 1 : .74);
      canvas.drawLine(
        head - direction * unit * .026 * (1 - t),
        head,
        Paint()
          ..color = _colors[i % _colors.length].withValues(alpha: opacity)
          ..strokeWidth = (i.isEven ? 4.5 : 3.2) * (1 - t * .5)
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  /// Where a screen-fan ribbon turns and where it peaks. With a [focus],
  /// every ribbon passes a spot inside the character's middle (so the art
  /// covers the crossing) and peaks in the open space above it.
  static ({Offset apex, Offset? via}) _aim(
    Size size,
    _Streamer r,
    Rect? focus,
  ) {
    final plain = Offset(size.width * r.x, size.height * r.y);
    if (focus == null || focus.isEmpty) return (apex: plain, via: null);
    // A small spread, kept within the solid middle of the drawing.
    final via =
        focus.center +
        Offset(
          math.sin(r.phase) * focus.width * .12,
          math.cos(r.phase * 1.7) * focus.height * .08,
        );
    // Below the header row, so the page title and steps stay readable.
    final ceiling = size.height * .14;
    final floor = math.max(ceiling + 8, focus.top - size.shortestSide * .04);
    final rise = ((r.y - .09) / .18).clamp(0.0, 1.0);
    // The fan keeps a clear column down the middle, a little wider than the
    // page title, so the ribbons fall on either side of it.
    final offset = plain.dx - size.width / 2;
    final dx =
        offset.sign *
        size.width *
        (.19 + (offset.abs() / size.width - .13) * .875);
    return (
      apex: Offset(size.width / 2 + dx, ceiling + (floor - ceiling) * rise),
      via: via,
    );
  }

  /// The way up to the character rises along the cannon's own side of the
  /// screen, outside the text and the order card, then sweeps in level with
  /// the character. Each ribbon varies a little so the bundle opens up.
  static Offset _bend(Size size, Offset mouth, Offset via, _Streamer r) {
    final outward = mouth.dx < size.width / 2 ? -1.0 : 1.0;
    final spread = .5 + .5 * math.sin(r.phase * 2.3);
    final lift = .5 + .5 * math.cos(r.phase * 1.3);
    return Offset(
      mouth.dx + outward * size.width * (.02 + .05 * spread),
      via.dy + size.height * (.02 + .06 * lift),
    );
  }

  double _tailDelay(Size size, _Streamer r) {
    final travel = size.height * (1 - r.y) + size.shortestSide * r.length + 48;
    return size.shortestSide * r.length / (travel / r.fall);
  }

  Offset _head(Size size, Offset origin, _Streamer r, double age) {
    if (age <= 0) return origin;
    final apex = Offset(size.width * r.x, size.height * r.y);
    if (age <= r.flight) {
      final t = age / r.flight;
      // Zero velocity at the apex, continuous with the following descent.
      return Offset.lerp(origin, apex, 1 - math.pow(1 - t, 3).toDouble())!;
    }
    final t = ((age - r.flight) / r.fall).clamp(0.0, 1.0);
    // Brief gravitational acceleration, then air resistance limits fall speed.
    double distance(double x) => x - .085 * (1 - math.exp(-x / .085));
    final descend = distance(t) / distance(1);
    final end = size.height + size.shortestSide * r.length + 48;
    final sway =
        (math.sin(age * .92 + r.phase) - math.sin(r.flight * .92 + r.phase)) *
        size.shortestSide *
        .037 *
        _smooth(t / .20);
    return Offset(apex.dx + sway, apex.dy + (end - apex.dy) * descend);
  }

  void _ribbon(
    Canvas canvas,
    Size size,
    Offset mouth,
    _Streamer r,
    double age, {
    double weight = 1,
    Rect? focus,
  }) {
    final aim = style == FireworksStyle.screenFan
        ? _aim(size, r, focus)
        : (apex: Offset(size.width * r.x, size.height * r.y), via: null);
    final spatialTrail = style == FireworksStyle.screenFan
        ? RibbonMotion(
            origin: mouth,
            apex: aim.apex,
            via: aim.via,
            bend: aim.via == null ? null : _bend(size, mouth, aim.via!, r),
            flight: r.flight,
            fall: r.fall,
            endY: size.height + size.shortestSide * r.length + 48,
            length: size.shortestSide * r.length,
            sway: size.shortestSide * .018,
            phase: r.phase,
          ).trail(age)
        : null;
    final lag =
        .14 +
        (_tailDelay(size, r) - .14) * _smooth((age - r.flight * .55) / 1.05);
    // Every point follows the preceding point's history. The strand bends at
    // its apex and lags behind the head instead of rotating as a rigid stick.
    final points = <Offset>[];
    final grow = _smooth(age / .48);
    for (var j = 0; j <= 24; j++) {
      final u = j / 24;
      final centre = spatialTrail?[j] ?? _head(size, mouth, r, age - lag * u);
      final envelope = math.sin(u * math.pi) * grow;
      final flutter =
          age * (1.15 + r.curls * .18) - u * math.pi * 2 * r.curls + r.phase;
      final bend = math.sin(age * .73 + r.phase + u * 2.4);
      if (spatialTrail != null) {
        final tangent =
            spatialTrail[math.min(j + 1, 24)] -
            spatialTrail[math.max(j - 1, 0)];
        final normal = tangent.distance > .01
            ? Offset(-tangent.dy, tangent.dx) / tangent.distance
            : const Offset(1, 0);
        // Small ripples travel along the paper, perpendicular to its current
        // direction. Taut while it shoots up (clean lines where the bouquets
        // cross); it only starts to flutter near the top of its flight.
        final loosen = .08 + .92 * _smooth((age - r.flight * .45) / .6);
        final wave = math.sin(flutter) * .007 + bend * .004;
        points.add(
          centre + normal * wave * size.shortestSide * envelope * loosen,
        );
        continue;
      }
      points.add(
        centre +
            Offset(
              (math.sin(flutter) * .019 + bend * .014) *
                  size.shortestSide *
                  envelope,
              math.cos(flutter * .78) * size.shortestSide * .007 * envelope,
            ),
      );
    }
    // Catmull-Rom to cubic Bézier: smoothly joined curves, not angular segments.
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 0; i < points.length - 1; i++) {
      final a = points[math.max(0, i - 1)];
      final b = points[i];
      final c = points[i + 1];
      final d = points[math.min(points.length - 1, i + 2)];
      final c1 = b + (c - a) / 6;
      final c2 = c - (d - b) / 6;
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, c.dx, c.dy);
    }
    // No time-based fade: the entire tail physically passes below the viewport.
    final opacity = _smooth(age / .10) * .94 * weight;
    final width = r.width * (size.shortestSide / 800).clamp(.7, 1.25);
    canvas.drawPath(
      path,
      Paint()
        ..color = r.color.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      path.shift(const Offset(-.6, -.4)),
      Paint()
        ..color = Colors.white.withValues(alpha: opacity * .30)
        ..style = PaintingStyle.stroke
        ..strokeWidth = width * .27
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_BirthdayPainter old) =>
      old.progress != progress ||
      old.streamers != streamers ||
      old.style != style ||
      old.layer != layer ||
      old.attachment != attachment ||
      old.focus != focus ||
      old.clear != clear;
}
