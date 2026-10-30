part of '../figure_motion.dart';

/// What an act asks of the body at one moment.
class _Frame {
  const _Frame({
    this.dx = 0,
    this.dy = 0,
    this.squash = 1,
    this.tilt = 0,
    this.armLeft = 0,
    this.armRight = 0,
    this.eyes = 1,
    this.mouth = 0,
    this.cheeks = 0,
    this.look = 0,
    this.spin = 0,
    this.face = 0,
    this.air = 0,
    this.joy = 0,
  });
  final double dx, dy, squash, tilt, armLeft, armRight, eyes, mouth, cheeks;
  final double look;

  /// Shut eyes smiling (^^) rather than asleep.
  final double joy;

  /// How far round it has turned (radians).
  final double spin;

  /// Which way a side-on friend should face for now (0: no preference).
  final double face;

  /// 1 while airborne: the body stretches with its speed.
  final double air;

  /// The same moment played bigger or smaller: how far it moves, leans,
  /// squashes and swings its arms. The face and turns stay as they are.
  _Frame scaled(double amp) => amp == 1
      ? this
      : _Frame(
          dx: dx * amp,
          dy: dy * amp,
          squash: 1 + (squash - 1) * amp,
          tilt: tilt * amp,
          armLeft: armLeft * amp,
          armRight: armRight * amp,
          eyes: eyes,
          mouth: mouth,
          cheeks: cheeks,
          look: look,
          spin: spin,
          face: face,
          air: air,
          joy: joy,
        );
}

_Frame _frame(Act act, double t, double travel, double dir, bool arms) =>
    switch (act) {
      Act.wave => _wave(t, dir, arms),
      Act.hop => _hops(t, dir),
      Act.wiggle => _wiggle(t, dir),
      Act.wonder => _wonder(t, dir),
      Act.stretch => _stretch(t),
      Act.doze => _doze(t),
      Act.giggle => _giggle(t),
      Act.eat => _eat(t, dir),
      Act.shake => _shake(t),
      Act.spin => _spinAround(t, dir),
      Act.lookAround => _lookAround(t, dir),
      Act.sneeze => _sneeze(t, dir),
      Act.hiccup => _hiccup(t),
      Act.shakeOff => _shakeOff(t),
      Act.yawn => _yawn(t),
      Act.laugh => _laugh(t),
      Act.shy => _shy(t, dir),
      Act.bounce => _bounce(t, dir),
      Act.dance => _dance(t, dir),
      Act.sniff => _sniff(t, dir),
      Act.hum => _hum(t, dir),
      Act.tumble => _tumble(t, dir),
      Act.float => _float(t, dir),
      Act.jelly => _jelly(t, dir),
      Act.peekaboo => _peekaboo(t, dir),
      Act.freeze => _freeze(t, dir),
      Act.sneak => _sneak(t, dir),
      Act.startle => _startle(t, dir),
      Act.heartbeat => _heartbeat(t),
      Act.dizzy => _dizzy(t, dir),
      Act.puff => _puff(t, dir),
      Act.waddle => _waddle(t),
      Act.popcorn => _popcorn(t),
      Act.yahoo => _yahoo(t, dir),
      Act.proud => _proud(t, dir),
      Act.enter => _Travel(travel).frame(t, dir, entering: true),
      Act.leave => _Travel(travel).frame(t, dir, entering: false),
    };
