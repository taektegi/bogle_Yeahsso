import 'dart:math' as math;
import 'dart:ui';

/// Time-based flight with a fixed-length paper trail, independent of frame rate.
/// Sampling by travelled distance prevents the strand shrinking at its apex.
class RibbonMotion {
  const RibbonMotion({
    required this.origin,
    required this.apex,
    required this.flight,
    required this.fall,
    required this.endY,
    required this.length,
    required this.sway,
    required this.phase,
    this.via,
    this.bend,
  });

  final Offset origin, apex;

  /// A point the ribbon passes on its way up, where it turns toward [apex].
  /// Used to send a whole bouquet through one spot behind the character, so
  /// the two cannons' crossing (and every turn) happens out of sight.
  final Offset? via;

  /// Pulls the way up to [via] into a curve (a quadratic control point), so
  /// the ribbon can rise along the side of the screen and sweep in, rather
  /// than cutting straight across whatever lies between.
  final Offset? bend;
  final double flight, fall, endY, length, sway, phase;

  /// Share of the flight spent reaching [via]: a quick shot, then a long,
  /// slowing fan-out above the character.
  static const _toVia = .32;

  /// Sideways air drag on the fan-out, as on the plain arc.
  static const _drag = 2.8;

  Offset head(double age) {
    if (age <= 0) return origin;
    final via = this.via;
    if (via != null) return _headVia(age, via);
    // Air drag slows the lateral flight without bringing it to a dead stop
    // at the apex. The same equation runs through ascent and descent.
    final drag = 2.8 / flight;
    final x =
        origin.dx +
        (apex.dx - origin.dx) *
            (1 - math.exp(-drag * age)) /
            (1 - math.exp(-drag * flight));
    if (age <= flight) {
      final t = age / flight;
      return Offset(x, origin.dy + (apex.dy - origin.dy) * (2 * t - t * t));
    }
    final elapsed = age - flight;
    const settle = .32;
    double distance(double t) => t - settle * (1 - math.exp(-t / settle));
    // Do not clamp time: the whole ribbon, not just its head, must exit below.
    final y = apex.dy + (endY - apex.dy) * distance(elapsed) / distance(fall);
    final wind =
        (1 - math.exp(-elapsed * elapsed)) *
        sway *
        (math.sin(elapsed * 1.1 + phase) - math.sin(phase));
    return Offset(x + wind, y);
  }

  Offset _headVia(double age, Offset via) {
    final first = flight * _toVia;
    if (age <= first) {
      final s = 1 - math.pow(1 - age / first, 1.3).toDouble();
      final c = bend ?? Offset.lerp(origin, via, .5)!;
      // Quadratic curve origin -> bend -> via.
      return origin * ((1 - s) * (1 - s)) +
          c * (2 * s * (1 - s)) +
          via * (s * s);
    }
    // After the turn, one clock runs through the fan-out and the fall.
    final u = (age - first) / (flight - first);
    // Air drag: sideways speed fades but never stops dead at the top, so
    // the paper rounds over instead of hooking back.
    final x =
        via.dx +
        (apex.dx - via.dx) *
            (1 - math.exp(-_drag * u)) /
            (1 - math.exp(-_drag));
    if (age <= flight) {
      return Offset(x, via.dy + (apex.dy - via.dy) * (2 * u - u * u));
    }
    final elapsed = age - flight;
    const settle = .32;
    double distance(double t) => t - settle * (1 - math.exp(-t / settle));
    final y = apex.dy + (endY - apex.dy) * distance(elapsed) / distance(fall);
    final wind =
        (1 - math.exp(-elapsed * elapsed)) *
        sway *
        (math.sin(elapsed * 1.1 + phase) - math.sin(phase));
    return Offset(x + wind, y);
  }

  /// A spatially sampled trail. Its tail follows the arc instead of stretching
  /// with speed; excess paper only unrolls during the first 180 milliseconds.
  List<Offset> trail(double age, {int segments = 24}) {
    final points = <Offset>[head(age)];
    final deployed =
        length * (1 - math.pow(1 - (age / .18).clamp(0.0, 1.0), 3));
    final spacing = deployed / segments;
    var previous = points.first;
    var travelled = 0.0;
    var nextDistance = spacing;
    // Fixed sampling step, never tied to display frames; bounded to one show.
    for (var t = age - .025; points.length <= segments; t -= .025) {
      final current = head(math.max(0, t));
      final step = (current - previous).distance;
      while (step > 0 &&
          nextDistance <= travelled + step &&
          points.length <= segments) {
        points.add(
          Offset.lerp(previous, current, (nextDistance - travelled) / step)!,
        );
        nextDistance += spacing;
      }
      travelled += step;
      previous = current;
      if (t <= 0) break;
    }
    while (points.length <= segments) {
      points.add(origin);
    }
    return points;
  }
}
