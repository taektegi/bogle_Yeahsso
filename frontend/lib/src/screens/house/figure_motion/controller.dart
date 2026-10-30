part of '../figure_motion.dart';

/// Plays a friend's acts and the life underneath them: breathing, blinking,
/// and the springy follow-through of a soft body.
///
/// Acts set where the body should be and roughly how it should be shaped;
/// damped springs then carry the shape there, so every change lags, swings
/// past and settles the way a soft toy would, and nothing ever jumps. When
/// the body is jolted — taking off or landing — the arms and the squash get
/// a kick from the change in speed, which is what makes a landing read as
/// heavy and the arms flop.
class FigureMotion {
  FigureMotion({math.Random? random, this.hasArms = false, this.facing = 0})
    : _random = random ?? math.Random() {
    _nextBlink = 1 + _random.nextDouble() * 2;
    _nextIdle = 1.6 + _random.nextDouble() * 2;
  }

  final math.Random _random;

  /// Whether the drawing's arms move on their own (a rigged friend); known
  /// once its drawing has been read.
  bool hasArms;

  /// Which way the drawing looks: -1 left, 1 right, 0 straight at us.
  /// A side-on friend turns around to face where it hops. Known once its
  /// drawing has been read.
  double facing;

  /// How it feels; changes what it picks to do by itself.
  Vibe vibe = Vibe.calm;
  double liveliness = 1;
  Act? _lastPat;
  final List<Act> _patDeck = [];

  static const _step = 1 / 240;

  double _time = 0;
  double _pending = 0;
  _Playing? _playing;

  /// Where the body stays when nothing plays (off stage after leaving).
  _Frame _rest = const _Frame();
  Act? _lastIdle;
  late double _nextIdle;

  final _squash = _Spring(1, hz: 4.2, damping: .42);
  final _tilt = _Spring(0, hz: 2.8, damping: .5);
  final _lean = _Spring(0, hz: 3.2, damping: .38);
  final _armL = _Spring(0, hz: 4.6, damping: .3);
  final _armR = _Spring(0, hz: 4.6, damping: .3);
  final _turn = _Spring(1, hz: 3.6, damping: .85);
  final _eyes = _Spring(1, hz: 7, damping: 1);
  final _mouth = _Spring(0, hz: 11, damping: .5);
  final _cheeks = _Spring(0, hz: 5, damping: .45);
  // Eyes dart; a spin follows its act closely.
  final _look = _Spring(0, hz: 9, damping: .8);
  final _spin = _Spring(0, hz: 9, damping: 1);
  final _joy = _Spring(0, hz: 6, damping: 1);

  /// Carries the body from wherever an interrupted act left it.
  final _carryX = _Spring(0, hz: 2.6, damping: 1);
  final _carryY = _Spring(0, hz: 3.4, damping: 1);

  double _x = 0, _y = 0, _vx = 0, _vy = 0;
  late double _nextBlink;
  double _blinkAt = -1;
  bool _doubleBlink = false;

  /// Which way it wants to face: -1 left, 1 right, 0 as drawn.
  double _heading = 0;

  FigurePose _pose = FigurePose.rest;
  FigurePose get pose => _pose;

  /// Seconds since this friend came on stage.
  double get time => _time;

  /// Seconds since the act now playing started.
  double? get actTime => switch (_playing) {
    final playing? => _time - playing.start,
    null => null,
  };

  Act? get acting => _playing?.act;

  /// Plays [act] now, cutting off whatever was playing. [travel] is how far
  /// an [Act.enter] or [Act.leave] goes and [direction] which way it faces
  /// (-1 left, 1 right); for [Act.wave], [direction] picks the arm on that
  /// side. [onDone] runs when the act is over, unless it is cut off.
  void play(
    Act act, {
    double travel = 1.5,
    double direction = 1,
    void Function()? onDone,
  }) {
    // Hand the body's current place to the carry springs so the new act
    // starts from here rather than snapping to its own first frame.
    _carryX
      ..value += _x
      ..velocity += _vx;
    _carryY
      ..value += _y
      ..velocity += _vy;
    _x = _y = _vx = _vy = 0;
    _rest = const _Frame();
    // The same act is never quite the same twice: a little bigger or
    // smaller each time. Acts the story times exactly stay as they are.
    final amp = _varies(act)
        ? (.9 + _random.nextDouble() * .25) * liveliness
        : 1.0;
    final start = _frame(act, 0, travel, direction, hasArms).scaled(amp);
    _x = start.dx;
    _y = start.dy;
    _carryX.value -= _x;
    _carryY.value -= _y;
    if (act == Act.enter || act == Act.leave) {
      // Arriving from off stage: no carrying across the room.
      _carryX
        ..value = 0
        ..velocity = 0;
      _carryY
        ..value = 0
        ..velocity = 0;
    }
    _playing = _Playing(act, _time, travel, direction, onDone, amp);
    if (act == Act.enter || act == Act.leave) {
      _heading = direction;
    }
  }

  /// Advances the clock by [dt] seconds. While [asleep] it keeps the sleeping
  /// pose; with [idle] it picks something to do now and then. [gaze] (-1..1)
  /// is something tempting to lean toward.
  void advance(
    double dt, {
    bool asleep = false,
    bool idle = true,
    double? gaze,
  }) {
    _pending += math.min(dt, .25);
    while (_pending >= _step) {
      _pending -= _step;
      _tick(_step, asleep: asleep, idle: idle, gaze: gaze);
    }
    _pose = _compose(asleep);
  }

  void _tick(
    double h, {
    required bool asleep,
    required bool idle,
    double? gaze,
  }) {
    _time += h;
    final playing = _playing;
    var f = _rest;
    if (playing != null) {
      final t = _time - playing.start;
      if (t >= playing.length) {
        _playing = null;
        if (playing.act == Act.leave) {
          _rest = _Frame(
            dx: _frame(
              Act.leave,
              t,
              playing.travel,
              playing.direction,
              hasArms,
            ).dx,
          );
          f = _rest;
        }
        _nextIdle = _time + _idleGap();
        playing.onDone?.call();
      } else {
        f = _frame(
          playing.act,
          t,
          playing.travel,
          playing.direction,
          hasArms,
        ).scaled(playing.amp);
      }
    } else if (idle && !asleep && gaze == null && _time >= _nextIdle) {
      _startIdle();
    }

    // Body position comes straight from the act; its change in speed kicks
    // the soft parts.
    final x = f.dx, y = f.dy;
    final vx = (x - _x) / h, vy = (y - _y) / h;
    final falling = _vy > 0;
    final jolt = vy - _vy;
    _x = x;
    _y = y;
    _vx = vx;
    _vy = vy;

    // Targets: the act's, over the sleeping pose or the idle one.
    final resting = asleep && playing == null;
    final reach = gaze == null ? 0.0 : .05 + gaze.abs() * .03;
    final squashTarget =
        f.squash + reach + math.min(.07, vy.abs() * .04) * f.air;
    final tiltTarget = f.tilt + (resting ? -.08 : 0) + (gaze ?? 0) * .14;
    final droop = resting ? -.14 : 0.0;

    // Landing (moving down, then stopped) squashes; any jolt flings the
    // arms, which then swing back on their springs.
    if (falling && jolt < -.4) _squash.velocity += jolt * 3.4;
    _armL.velocity += jolt * 3;
    _armR.velocity += jolt * 3;

    _squash.step(squashTarget, h);
    _tilt.step(tiltTarget, h);
    _lean.step((vx * .09).clamp(-.22, .22), h);
    _armL.step(f.armLeft + droop, h);
    _armR.step(f.armRight + droop, h);
    _eyes.step(resting ? .1 : f.eyes, h);
    _mouth.step(f.mouth, h);
    _cheeks.step(f.cheeks, h);
    _look.step(f.look, h);
    _spin.step(f.spin, h);
    _joy.step(f.joy, h);
    _carryX.step(0, h);
    _carryY.step(0, h);
    // Side-on: faces where it's heading, or where an act has it look.
    final towards = f.face != 0 ? f.face : _heading;
    _turn.step(facing == 0 || towards == 0 || towards == facing ? 1 : -1, h);
    _blink(h);
  }

  void _startIdle() {
    final choices = [
      for (final act in idleActs)
        if (act != _lastIdle)
          for (var i = 0; i < _weight(act); i++) act,
    ];
    final act = choices[_random.nextInt(choices.length)];
    _lastIdle = act;
    play(act, direction: _random.nextBool() ? 1 : -1);
  }

  /// 모든 터치 동작을 한 번씩 섞어 사용한다. 한 바퀴 경계에서도 바로 반복하지 않는다.
  Act patAct() {
    if (_patDeck.isEmpty) {
      _patDeck.addAll(patActs.toSet().toList()..shuffle(_random));
    }
    if (_patDeck.length > 1 &&
        (_patDeck.last == _lastPat || _patDeck.last == acting)) {
      var index = _patDeck.indexWhere(
        (act) => act != _lastPat && act != acting,
      );
      if (index < 0) index = _patDeck.indexWhere((act) => act != _lastPat);
      final last = _patDeck.last;
      _patDeck[_patDeck.length - 1] = _patDeck[index];
      _patDeck[index] = last;
    }
    final act = _patDeck.removeLast();
    _lastPat = act;
    return act;
  }

  /// How likely [act] is picked by itself, by how the friend feels. Every
  /// idle act stays possible when calm.
  int _weight(Act act) {
    final base = switch (act) {
      Act.hop => 3,
      Act.wave => hasArms ? 3 : 2,
      Act.sneeze || Act.hiccup || Act.shakeOff || Act.tumble => 1,
      _ => 2,
    };
    final lively = const {
      Act.hop,
      Act.wiggle,
      Act.spin,
      Act.bounce,
      Act.dance,
      Act.hiccup,
      Act.tumble,
      Act.jelly,
      Act.peekaboo,
      Act.freeze,
      Act.startle,
      Act.dizzy,
      Act.waddle,
      Act.popcorn,
      Act.yahoo,
    }.contains(act);
    return switch (vibe) {
      Vibe.calm => base,
      Vibe.cheerful =>
        lively || act == Act.hum || act == Act.wave ? base * 2 : base,
      Vibe.sleepy => switch (act) {
        Act.yawn => 6,
        Act.hum || Act.wonder || Act.lookAround || Act.shy || Act.float => base,
        _ => lively ? 0 : 1,
      },
      Vibe.hungry => switch (act) {
        Act.sniff => 6,
        Act.lookAround || Act.wonder => base * 2,
        _ => lively ? 1 : base,
      },
    };
  }

  /// Seconds until it does something by itself again.
  double _idleGap() =>
      (switch (vibe) {
        Vibe.cheerful => 2.6 + _random.nextDouble() * 3.4,
        Vibe.sleepy => 4.5 + _random.nextDouble() * 5,
        _ => 3.2 + _random.nextDouble() * 4.5,
      }) /
      liveliness;

  /// Whether [act] plays a little bigger or smaller each time.
  static bool _varies(Act act) => switch (act) {
    Act.eat || Act.enter || Act.leave || Act.doze || Act.stretch => false,
    _ => true,
  };

  void _blink(double h) {
    if (_blinkAt < 0 && _time >= _nextBlink) {
      _blinkAt = _time;
      _doubleBlink = _random.nextDouble() < .22;
    }
    if (_blinkAt >= 0 && _time - _blinkAt > (_doubleBlink ? .42 : .2)) {
      _blinkAt = -1;
      _nextBlink = _time + 2.2 + _random.nextDouble() * 3.6;
    }
  }

  double get _blinkShut {
    if (_blinkAt < 0) return 0;
    final t = _time - _blinkAt;
    // Shuts fast, opens a little slower.
    double one(double t) => t < .06
        ? t / .06
        : t < .09
        ? 1
        : t < .2
        ? 1 - (t - .09) / .11
        : 0;
    return math.max(one(t), _doubleBlink ? one(t - .22) : 0);
  }

  FigurePose _compose(bool asleep) {
    final resting = asleep && _playing == null;
    // Breathing sits on top of everything; sleeping breath is slower and
    // deeper.
    final period = resting ? 4.2 : 2.8;
    final breath =
        math.sin(_time * 2 * math.pi / period) * (resting ? .022 : .018);
    final sy = _squash.value * (1 + breath);
    // Soft bodies keep their volume: taller is thinner.
    final sx = math.pow(sy, -.85).toDouble();
    final sway = math.sin(_time * 2 * math.pi / period - .9) * .035;
    return FigurePose(
      dx: _x + _carryX.value,
      dy: _y + _carryY.value,
      scaleX: sx,
      scaleY: sy,
      tilt: _tilt.value,
      lean: _lean.value,
      armLeft: _armL.value + sway,
      armRight: _armR.value + sway,
      eyes: (_eyes.value * (1 - _blinkShut)).clamp(0.08, 1.3),
      mouth: _mouth.value.clamp(-.7, 1.3),
      cheeks: _cheeks.value.clamp(0.0, 1.3),
      look: _look.value,
      // A spin shows as the drawing turning edge-on and round.
      turn: _turn.value * math.cos(_spin.value),
      joy: _joy.value.clamp(0.0, 1.0),
    );
  }

  /// The pose for a still screen (reduced motion).
  static FigurePose still({required bool asleep}) => asleep
      ? const FigurePose(tilt: -.08, eyes: .1, armLeft: -.14, armRight: -.14)
      : FigurePose.rest;
}

class _Playing {
  _Playing(
    this.act,
    this.start,
    this.travel,
    this.direction,
    this.onDone,
    this.amp,
  ) : length = actLength(act, travel);
  final Act act;
  final double start;
  final double travel;
  final double direction;
  final void Function()? onDone;
  final double length;

  /// How big it plays this time (1 as made).
  final double amp;
}

/// Seconds an act lasts.
double actLength(Act act, [double travel = 1.5]) => switch (act) {
  Act.wave => 2.7,
  Act.hop => 2.45,
  Act.wiggle => 3.0,
  Act.wonder => 2.5,
  Act.stretch => 3.1,
  Act.doze => 3.3,
  Act.giggle => 1.15,
  Act.eat => eatLength,
  Act.shake => 1.1,
  Act.spin => 1.9,
  Act.lookAround => 3.2,
  Act.sneeze => 2.5,
  Act.hiccup => 2.6,
  Act.shakeOff => 1.9,
  Act.yawn => 2.9,
  Act.laugh => 2.2,
  Act.shy => 2.4,
  Act.bounce => 1.8,
  Act.dance => 4.3,
  Act.sniff => 2.4,
  Act.hum => 3.2,
  Act.tumble => 2.7,
  Act.float => 3.7,
  Act.jelly => 2.6,
  Act.peekaboo => 2.8,
  Act.freeze => 3.2,
  Act.sneak => 4.2,
  Act.startle => 2.1,
  Act.heartbeat => 2.4,
  Act.dizzy => 3.0,
  Act.puff => 3.1,
  Act.waddle => 2.6,
  Act.popcorn => 2.3,
  Act.yahoo => 3.1,
  Act.proud => 2.6,
  Act.enter || Act.leave => _Travel(travel).length,
};
