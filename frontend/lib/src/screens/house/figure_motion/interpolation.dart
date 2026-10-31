part of '../figure_motion.dart';

// ─── Hops ──────────────────────────────────────────────────────────────────

class _Hop {
  const _Hop({
    required this.at,
    required this.crouch,
    required this.depth,
    required this.air,
    required this.height,
    required this.travel,
  });

  /// When the crouch starts.
  final double at;

  /// How long it crouches, and how low (squash) before taking off.
  final double crouch;
  final double depth;
  final double air;
  final double height;
  final double travel;

  double get takeoff => at + crouch;
  double get landing => takeoff + air;
}

/// A run of hops. Gravity is the same for every hop, so small and big
/// ones read as the same body; the body leans into each leap and rights
/// itself coming down, so its path is an arc rather than up-and-down.
_Frame _hopFrame(List<_Hop> hops, double t, double dir, {double startX = 0}) {
  var x = startX;
  for (final hop in hops) {
    if (t < hop.at) {
      return _Frame(dx: x);
    }
    if (t < hop.takeoff) {
      final u = (t - hop.at) / hop.crouch;
      // Sinks into the crouch, holding the bottom a moment before letting go.
      final sink = _ease(math.min(1, u * 1.25));
      return _Frame(
        dx: x,
        squash: 1 - (1 - hop.depth) * sink,
        // Leans back a touch, away from where it's going.
        tilt: -(hop.travel * dir).sign * .04 * sink,
      );
    }
    if (t < hop.landing) {
      final u = (t - hop.takeoff) / hop.air;
      final leap = hop.travel * dir;
      return _Frame(
        dx: x + leap * u,
        dy: -hop.height * 4 * u * (1 - u),
        // Pops out of the crouch straight into the stretch.
        squash: 1 + (1 - hop.depth) * .5 * (1 - _ease(math.min(1, u * 4))),
        tilt: leap.sign * .11 * (1 - 2 * u),
        air: 1,
      );
    }
    x += hop.travel * dir;
  }
  return _Frame(dx: x);
}

/// Hopping on or off stage: small bouncy hops, each bouncing straight into
/// the next, and a last short one to land in place.
class _Travel {
  _Travel(this.distance) : count = (distance / .42).ceil().clamp(3, 7);
  final double distance;
  final int count;

  static const _air = .32, _crouch = .09, _first = .16, _height = .12;

  /// The last hop covers less ground: the arrival.
  double get _unit => distance / (count - .45);

  double get length => _first + count * (_air + _crouch) - _crouch + .55;

  List<_Hop> get _hops => [
    for (var i = 0; i < count; i++)
      _Hop(
        at: i == 0 ? 0 : _first + i * (_air + _crouch) - _crouch,
        crouch: i == 0 ? _first : _crouch,
        depth: i == count - 1 ? .86 : .9,
        air: i == count - 1 ? _air * .85 : _air,
        height: i == count - 1 ? _height * .7 : _height,
        travel: _unit * (i == count - 1 ? .55 : 1),
      ),
  ];

  _Frame frame(double t, double dir, {required bool entering}) {
    // Entering it starts off stage and ends at home; leaving is the reverse.
    final f = _hopFrame(_hops, t, dir, startX: entering ? -dir * distance : 0);
    return _Frame(
      dx: f.dx,
      dy: f.dy,
      squash: f.squash,
      tilt: f.tilt,
      armLeft: .12 * f.air,
      armRight: .12 * f.air,
      air: f.air,
    );
  }
}

// ─── Curves ────────────────────────────────────────────────────────────────

double _ease(double u) => u * u * (3 - 2 * u);

/// 0 outside [from]..[to], 1 inside, easing in and out over [fade].
double _window(double t, double from, double to, double fade) {
  if (t <= from || t >= to) return 0;
  return _ease(math.min(1, math.min(t - from, to - t) / fade));
}

/// Rises from 0 at [from] to 1 at [peak], holds until [until], then falls
/// back to 0 at the same speed it rose.
double _bump(double t, double from, double peak, double until) {
  final rise = peak - from;
  if (t <= from || t >= until + rise) return 0;
  if (t < peak) return _ease((t - from) / rise);
  if (t <= until) return 1;
  return 1 - _ease((t - until) / rise);
}

/// A key-framed curve through [keys] (time, value), as an animator's spline:
/// smooth through each key, flat at the first and last and at every peak
/// and valley, and never overshooting between two keys.
double _keys(double t, List<(double, double)> keys) {
  if (t <= keys.first.$1) return keys.first.$2;
  if (t >= keys.last.$1) return keys.last.$2;
  var i = 0;
  while (t > keys[i + 1].$1) {
    i++;
  }
  final (t0, v0) = keys[i];
  final (t1, v1) = keys[i + 1];
  final h = t1 - t0;
  final m0 = _tangent(keys, i), m1 = _tangent(keys, i + 1);
  final s = (t - t0) / h, s2 = s * s, s3 = s2 * s;
  return (2 * s3 - 3 * s2 + 1) * v0 +
      (s3 - 2 * s2 + s) * h * m0 +
      (-2 * s3 + 3 * s2) * v1 +
      (s3 - s2) * h * m1;
}

double _tangent(List<(double, double)> keys, int i) {
  if (i == 0 || i == keys.length - 1) return 0;
  final (ta, va) = keys[i - 1];
  final (tb, vb) = keys[i];
  final (tc, vc) = keys[i + 1];
  final before = (vb - va) / (tb - ta), after = (vc - vb) / (tc - tb);
  if (before * after <= 0) return 0;
  final m = (vc - va) / (tc - ta);
  // Fritsch–Carlson: keep the curve between its keys.
  final limit = 3 * math.min(before.abs(), after.abs());
  return m.sign * math.min(m.abs(), limit);
}

/// A damped spring chasing a target: [hz] is how quickly it swings and
/// [damping] how soon it settles (1 settles without swinging past).
class _Spring {
  _Spring(this.value, {required double hz, required double damping})
    : _omega = 2 * math.pi * hz,
      _zeta = damping;
  double value;
  double velocity = 0;
  final double _omega, _zeta;

  void step(double target, double h) {
    final a =
        _omega * _omega * (target - value) - 2 * _zeta * _omega * velocity;
    // Semi-implicit Euler: stable at this step size.
    velocity += a * h;
    value += velocity * h;
  }
}
