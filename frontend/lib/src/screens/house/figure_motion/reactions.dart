part of '../figure_motion.dart';

// ─── The acts ──────────────────────────────────────────────────────────────

/// Anticipation (the arm dips in, the body leans away), the arm swings up
/// past its mark, three and a half waves while the body sways against them,
/// and down again. [side] picks the arm: 1 right, -1 left.
_Frame _wave(double t, double side, bool arms) {
  final arm = _keys(t, const [
    (0, 0),
    (.2, -.14),
    (.46, .2),
    (2.02, .18),
    (2.45, 0),
  ]);
  final waving = _window(t, .46, 2.02, .16);
  final phase = (t - .46) * 2 * math.pi * 2.1;
  final wag = math.sin(phase) * .28 * waving;
  final other = _keys(t, const [(0, 0), (.46, .08), (2.02, .08), (2.45, 0)]);
  // A friend without arms says hello with its whole body instead.
  final rock = arms ? 0.0 : math.sin(phase * .62) * .075 * waving;
  final tilt =
      side *
      (_keys(t, const [
            (0, 0),
            (.2, -.05),
            (.46, .07),
            (2.02, .055),
            (2.5, 0),
          ]) -
          math.sin(phase) * .018 * waving);
  final open = arm + wag;
  return _Frame(
    dy: _keys(t, const [(0, 0), (.2, .004), (.42, -.028), (.66, 0)]),
    squash: _keys(t, const [
      (0, 1),
      (.2, .95),
      (.46, 1.045),
      (2.02, 1.02),
      (2.5, 1),
    ]),
    tilt: tilt + rock,
    armLeft: side < 0 ? open : other,
    armRight: side < 0 ? other : open,
  );
}

/// Hop, hop, HOP: the first two travel a little and bounce straight into
/// each other, the third crouches deeper and flies higher with both arms up.
_Frame _hops(double t, double dir) {
  final hops = [
    const _Hop(
      at: 0,
      crouch: .2,
      depth: .86,
      air: .34,
      height: .1,
      travel: .07,
    ),
    const _Hop(
      at: .54,
      crouch: .12,
      depth: .87,
      air: .34,
      height: .1,
      travel: -.07,
    ),
    const _Hop(
      at: 1.0,
      crouch: .26,
      depth: .8,
      air: .52,
      height: .25,
      travel: 0,
    ),
  ];
  final f = _hopFrame(hops, t, dir);
  // 만세 on the big one: arms fly up on the way up and float down after.
  final cheer = _keys(t, const [
    (0, 0),
    (1.26, -.06),
    (1.5, .42),
    (1.78, .3),
    (2.2, 0),
  ]);
  return _Frame(
    dx: f.dx,
    dy: f.dy,
    squash: f.squash,
    tilt: f.tilt,
    armLeft: cheer,
    armRight: cheer,
    // A happy squint as it lands.
    eyes: 1 - .55 * _bump(t, 1.76, 1.84, 2.1),
    joy: _bump(t, 1.7, 1.8, 2.1),
    air: f.air,
  );
}

/// Sways side to side, bouncing down on every beat, the arms taking turns.
_Frame _wiggle(double t, double dir) {
  final env = _window(t, .15, 2.75, .3);
  final p = (t - .15) * 2 * math.pi * .95;
  final s = math.sin(p) * dir;
  return _Frame(
    dx: s * .018 * env,
    dy: -math.sin(p).abs() * .026 * env,
    squash: 1 - (1 - math.sin(p).abs()) * .06 * env,
    tilt: s * .11 * env,
    armLeft: math.max(0, -s) * .38 * env,
    armRight: math.max(0, s) * .38 * env,
  );
}

/// 갸우뚱: leans its head over slowly, wonders (and blinks), then pops back
/// up as if it had an idea.
_Frame _wonder(double t, double dir) {
  final tilt = _keys(t, const [
    (0, 0),
    (.55, -.17),
    (1.3, -.15),
    (1.52, .03),
    (2.1, 0),
  ]);
  final scratch = _keys(t, const [(0, 0), (.55, .22), (1.3, .2), (1.6, 0)]);
  return _Frame(
    dy: _keys(t, const [(0, 0), (1.3, .006), (1.48, -.05), (1.7, 0)]),
    squash: _keys(t, const [
      (0, 1),
      (.55, 1),
      (1.28, .94),
      (1.48, 1.08),
      (1.75, 1),
    ]),
    tilt: tilt * dir,
    armLeft: dir > 0 ? scratch : 0,
    armRight: dir > 0 ? 0 : scratch,
    eyes: 1 - _bump(t, .86, .92, 1.02),
  );
}

/// 기지개: crouches, rises into a long stretch with its eyes shut and arms
/// trembling up high, then lets go with a bounce.
_Frame _stretch(double t) {
  final up = _keys(t, const [
    (0, 0),
    (.35, -.1),
    (1.1, .46),
    (1.9, .5),
    (2.25, 0),
  ]);
  final tremble =
      math.sin(t * 2 * math.pi * 9) * .03 * _window(t, 1.1, 1.9, .1);
  return _Frame(
    dy: _keys(t, const [(0, 0), (1.1, -.02), (1.9, -.02), (2.15, 0)]),
    squash: _keys(t, const [
      (0, 1),
      (.35, .9),
      (1.1, 1.16),
      (1.9, 1.14),
      (2.15, .9),
      (2.5, 1.02),
      (3.0, 1),
    ]),
    tilt: _keys(t, const [(0, 0), (1.1, .03), (1.9, -.03), (2.4, 0)]),
    armLeft: up + tremble,
    armRight: up - tremble,
    eyes: 1 - _bump(t, .35, .55, 2.0) * .9,
  );
}

/// Nods off twice — starting awake at the first — and ends in the sleeping
/// pose, so sleep carries on from here without a jump.
_Frame _doze(double t) => _Frame(
  squash: _keys(t, const [
    (0, 1),
    (.9, .94),
    (1.08, 1.03),
    (2.5, .95),
    (3.3, 1),
  ]),
  tilt: _keys(t, const [
    (0, 0),
    (.9, -.07),
    (1.08, .02),
    (2.5, -.06),
    (3.3, -.08),
  ]),
  armLeft: _keys(t, const [(0, 0), (.9, -.1), (1.08, .05), (3.3, -.14)]),
  armRight: _keys(t, const [(0, 0), (.9, -.1), (1.08, .05), (3.3, -.14)]),
  eyes: _keys(t, const [
    (0, 1),
    (.9, .35),
    (1.08, 1),
    (1.7, .8),
    (2.6, .12),
    (3.3, .1),
  ]),
);

/// Ticklish: squashes, bounces up with its arms flapping, wriggles.
_Frame _giggle(double t) {
  final wriggle =
      math.sin(t * 2 * math.pi * 3.2) * .05 * _window(t, .25, 1.0, .2);
  final flap = _keys(t, const [
    (0, 0),
    (.1, -.1),
    (.3, .36),
    (.52, .06),
    (.72, .22),
    (1.1, 0),
  ]);
  return _Frame(
    dy: _keys(t, const [(0, 0), (.1, 0), (.3, -.06), (.52, 0)]),
    squash: _keys(t, const [
      (0, 1),
      (.1, .86),
      (.3, 1.1),
      (.52, .96),
      (.72, 1.02),
      (1.1, 1),
    ]),
    tilt: wriggle,
    armLeft: flap,
    armRight: flap,
    eyes: 1 - .6 * _bump(t, .08, .16, .8),
    joy: _bump(t, .06, .14, .85),
  );
}

/// Eating, beat by beat. It spots the snack (eyes wide, perking up and
/// leaning in), opens wide before each bite and snaps shut on it with a
/// little lunge, then chews — mouth working, cheeks puffed, eyes squeezed
/// happy, the body bobbing with each chew. After the last bite: a gulp that
/// squashes and stretches the body, then a satisfied open-mouthed "yum".
/// [dir] is the side the snack is held on.
_Frame _eat(double t, double dir) {
  const chewHz = 3.4, gulp = 2.48;
  final spot = _bump(t, 0, .22, .42);
  var mouth = .18 * spot;
  var chewing = 0.0, chew = 0.0;
  for (final (i, bite) in eatBites.indexed) {
    final opening = bite - .3;
    final next = i + 1 < eatBites.length ? eatBites[i + 1] - .3 : gulp;
    if (t >= opening && t < bite - .03) {
      // "아~": wide open, held until the snack is in.
      mouth = 1.05 * _ease(math.min(1, (t - opening) / .2));
    } else if (t >= bite - .03 && t < next) {
      chewing = _window(t, bite - .03, next + .12, .1);
      chew = .5 - .5 * math.cos(2 * math.pi * chewHz * math.max(0, t - bite));
      mouth = -.55 + .42 * chew * chewing;
    }
  }
  var lunge = 0.0;
  for (final bite in eatBites) {
    lunge += _bump(t, bite - .1, bite, bite + .02);
  }
  final after = t >= gulp;
  if (after) {
    mouth = _keys(t, const [
      (gulp, -.5),
      (2.6, -.3),
      (2.74, .4),
      (2.9, .38),
      (eatLength, 0),
    ]);
  }
  final eyes = after
      ? 1 + .1 * _bump(t, 2.5, 2.58, 2.62) - .55 * _bump(t, 2.66, 2.74, 2.88)
      : 1 + .2 * spot - chewing * (.6 - .12 * chew);
  return _Frame(
    dx: dir * .018 * lunge,
    dy: .012 * lunge - .007 * chew * chewing - .03 * _bump(t, 2.64, 2.74, 2.76),
    squash: after
        ? _keys(t, const [(gulp, 1), (2.57, .93), (2.68, 1.06), (2.82, 1)])
        : (1 + .035 * spot) * (1 - .07 * lunge) * (1 - .035 * chew * chewing),
    tilt:
        dir * .05 * _window(t, 0, gulp + .1, .3) +
        math.sin(t * 2 * math.pi * chewHz / 2) * .025 * chewing,
    armLeft: .1 * spot + .12 * _bump(t, 2.64, 2.74, 2.86),
    armRight: .1 * spot + .12 * _bump(t, 2.64, 2.74, 2.86),
    eyes: eyes,
    mouth: mouth,
    cheeks: after ? _keys(t, const [(gulp, 1), (2.6, 0)]) : chewing,
    // Chewing with its eyes squeezed happy, and a smile after the "yum".
    joy: after ? _bump(t, 2.62, 2.72, 2.9) : chewing,
  );
}

_Frame _shake(double t) {
  final env = _window(t, .12, 1.0, .12);
  return _Frame(
    squash: _keys(t, const [(0, 1), (.12, .95), (.9, .98), (1.1, 1)]),
    tilt: math.sin((t - .12) * 2 * math.pi * 3) * .1 * env,
    eyes: 1 - .85 * _bump(t, .1, .2, .9),
  );
}

/// 빙그르르: one hop, turning a full circle in the air — arms flung out,
/// slow at the start and end of the turn — and a happy squint on landing.
_Frame _spinAround(double t, double dir) {
  const hop = _Hop(
    at: 0,
    crouch: .22,
    depth: .86,
    air: .6,
    height: .17,
    travel: 0,
  );
  final f = _hopFrame(const [hop], t, dir);
  final u = ((t - hop.takeoff) / hop.air).clamp(0.0, 1.0);
  final out = _keys(t, const [
    (0, 0),
    (.2, -.08),
    (.4, .34),
    (.8, .3),
    (1.1, 0),
  ]);
  return _Frame(
    dy: f.dy,
    squash: f.squash,
    tilt: dir * .05 * f.air,
    armLeft: out,
    armRight: out,
    spin: 2 * math.pi * _ease(u),
    eyes: 1 - .6 * _bump(t, .84, .92, 1.25),
    joy: _bump(t, .8, .9, 1.25),
    air: f.air,
  );
}

/// 두리번두리번: a quick glance one way (eyes first, the body following),
/// a blink as it switches, the other way, then back — and a small tilt, as
/// if wondering what it was looking for.
_Frame _lookAround(double t, double dir) {
  final look =
      dir *
      _keys(t, const [
        (0, 0),
        (.22, 1),
        (1.0, 1),
        (1.22, -1),
        (2.05, -1),
        (2.3, 0),
      ]);
  final wonder = _keys(t, const [(0, 0), (2.3, 0), (2.6, .06), (2.95, 0)]);
  return _Frame(
    dx: look * .012,
    squash: 1 + .015 * look.abs(),
    tilt: look * .045 + dir * wonder,
    look: look,
    face: look.abs() > .5 ? look.sign : 0,
    eyes: 1 - _bump(t, 1.04, 1.1, 1.14),
    armLeft: .08 * math.max(0, -look),
    armRight: .08 * math.max(0, look),
  );
}

/// 에취!
_Frame _sneeze(double t, double dir) {
  final shake =
      math.sin((t - 1.5) * 2 * math.pi * 4) * .04 * _window(t, 1.5, 2.2, .1);
  return _Frame(
    dx:
        dir *
        _keys(t, const [
          (0, 0),
          (.92, -.01),
          (1.0, .035),
          (1.4, .01),
          (1.8, 0),
        ]),
    dy: _keys(t, const [
      (0, 0),
      (.92, -.01),
      (1.0, .01),
      (1.12, -.035),
      (1.3, 0),
    ]),
    squash: _keys(t, const [
      (0, 1),
      (.35, 1.05),
      (.5, 1.03),
      (.8, 1.1),
      (.92, 1.12),
      (1.0, .84),
      (1.12, 1.04),
      (1.3, .98),
      (1.6, 1),
    ]),
    tilt:
        dir *
            _keys(t, const [
              (0, 0),
              (.35, -.05),
              (.5, -.04),
              (.85, -.1),
              (.92, -.11),
              (1.0, .14),
              (1.15, .02),
              (1.35, .05),
              (1.6, 0),
            ]) +
        shake,
    eyes: _keys(t, const [
      (0, 1),
      (.35, .7),
      (.5, .8),
      (.85, .25),
      (.92, .2),
      (1.0, .08),
      (1.3, .1),
      (1.55, 1),
    ]),
    mouth: _keys(t, const [
      (0, 0),
      (.35, .35),
      (.5, .3),
      (.85, .75),
      (.92, .85),
      (.97, -.4),
      (1.03, .7),
      (1.25, .2),
      (1.45, 0),
    ]),
    armLeft: _keys(t, const [
      (0, 0),
      (.85, .2),
      (.95, .25),
      (1.0, -.2),
      (1.3, .05),
      (1.6, 0),
    ]),
    armRight: _keys(t, const [
      (0, 0),
      (.85, .2),
      (.95, .25),
      (1.0, -.2),
      (1.3, .05),
      (1.6, 0),
    ]),
  );
}

/// 딸꾹! ×3: each pops up fast and drops back, eyes and mouth flashing wide
/// open, the body jerking a different way each time.
_Frame _hiccup(double t) {
  var dy = 0.0, squash = 1.0, pop = 0.0, tilt = 0.0;
  for (final (i, at) in hiccupAt.indexed) {
    if (t < at - .05 || t > at + .32) continue;
    dy = _keys(t, [(at - .05, 0), (at + .04, -.05), (at + .3, 0)]);
    squash = _keys(t, [
      (at - .05, 1),
      (at + .02, 1.09),
      (at + .2, .95),
      (at + .32, 1),
    ]);
    pop = _bump(t, at - .03, at + .02, at + .12);
    tilt = (i.isEven ? 1 : -1) * .05 * pop;
  }
  return _Frame(
    dy: dy,
    squash: squash,
    tilt: tilt,
    eyes: 1 + .22 * pop,
    mouth: .35 * pop,
    armLeft: .15 * pop,
    armRight: .15 * pop,
  );
}

/// 부르르: tucks in, then shakes hard from side to side — fast, and dying
/// away — arms flapping and eyes squeezed shut, then a relieved bounce.
_Frame _shakeOff(double t) {
  final env =
      _window(t, .2, 1.35, .12) * (1 - .5 * ((t - .2) / 1.15).clamp(0.0, 1.0));
  final p = (t - .2) * 2 * math.pi * 5.5;
  final flap = math.sin(p + 1.2) * .25 * env;
  return _Frame(
    dx: math.sin(p + .8) * .012 * env,
    dy: -.02 * _bump(t, 1.45, 1.55, 1.57),
    squash:
        _keys(t, const [
          (0, 1),
          (.2, .93),
          (.3, 1.01),
          (1.35, .97),
          (1.55, 1.03),
          (1.9, 1),
        ]) +
        math.sin(p * 2) * .03 * env,
    tilt: math.sin(p) * .13 * env,
    armLeft: flap,
    armRight: -flap,
    eyes: 1 - .85 * _bump(t, .15, .25, 1.3),
    mouth: -.3 * env,
  );
}

/// 하암~: breathes in — stretching up, arms rising, mouth opening slowly and
/// eyes squeezing shut — holds the big yawn with a tremble, lets it go and
/// smacks its lips twice.
_Frame _yawn(double t) {
  final tremble =
      math.sin(t * 2 * math.pi * 7) * .015 * _window(t, 1.0, 1.75, .1);
  final smack = _window(t, 2.0, 2.55, .08);
  final arms = _keys(t, const [(0, 0), (1.0, .3), (1.75, .32), (2.2, 0)]);
  return _Frame(
    dy: _keys(t, const [(0, 0), (1.0, -.012), (1.75, -.012), (2.05, 0)]),
    squash:
        _keys(t, const [
          (0, 1),
          (.5, .97),
          (1.0, 1.08),
          (1.75, 1.07),
          (2.05, .97),
          (2.4, 1),
        ]) +
        tremble,
    tilt: _keys(t, const [(0, 0), (1.0, -.04), (1.75, -.05), (2.2, 0)]),
    armLeft: arms,
    armRight: arms,
    eyes: _keys(t, const [
      (0, 1),
      (.6, .5),
      (1.0, .1),
      (1.8, .12),
      (2.3, .55),
      (2.6, .7),
      (2.9, 1),
    ]),
    mouth:
        _keys(t, const [
          (0, 0),
          (.45, .3),
          (1.0, 1.15),
          (1.75, 1.2),
          (2.0, 0),
        ]) +
        (-.25 + .25 * math.cos(2 * math.pi * 3.6 * (t - 2.0))) * smack,
  );
}

/// 깔깔: rocks back laughing in quick peals — a bounce and an open mouth on
/// every one — with its eyes squeezed happy and its cheeks pink.
_Frame _laugh(double t) {
  final env = _window(t, .15, 1.85, .15);
  final p = (t - .15) * 2 * math.pi * 4.2;
  final peal = .5 + .5 * math.sin(p);
  return _Frame(
    dy: -.018 * peal * env,
    squash: 1 + .045 * (peal - .5) * env,
    tilt: -.07 * env + math.sin(p * .5) * .03 * env,
    armLeft: (.12 + .1 * peal) * env,
    armRight: (.12 + .1 * peal) * env,
    eyes: 1 - .85 * env,
    joy: env,
    mouth: (.3 + .5 * peal) * env,
    cheeks: .7 * env,
  );
}

/// 부끄부끄: shrinks a little and turns aside, blushing, and sways shyly with
/// its eyes squeezed in a smile; it peeks back once, then perks up.
_Frame _shy(double t, double dir) {
  final env = _window(t, .2, 2.1, .3);
  final sway = math.sin((t - .2) * 2 * math.pi * 1.1) * env;
  final peek = _bump(t, 1.15, 1.25, 1.45);
  return _Frame(
    dx: -dir * .012 * env,
    squash: 1 - .05 * env,
    tilt: dir * (.07 * env + .035 * sway),
    armLeft: .14 * env,
    armRight: .14 * env,
    eyes: 1 - .75 * env + .55 * peek,
    joy: env * (1 - peek),
    cheeks: .7 * env,
    look: -dir * .6 * env,
  );
}

/// 통통: three bouncy hops in place, each smaller than the last, landing
/// with a happy squint.
_Frame _bounce(double t, double dir) {
  const hops = [
    _Hop(at: 0, crouch: .14, depth: .88, air: .3, height: .07, travel: 0),
    _Hop(at: .46, crouch: .1, depth: .9, air: .26, height: .05, travel: 0),
    _Hop(at: .84, crouch: .08, depth: .92, air: .22, height: .035, travel: 0),
  ];
  final f = _hopFrame(hops, t, dir);
  final squint = _bump(t, 1.12, 1.2, 1.5);
  return _Frame(
    dy: f.dy,
    squash: f.squash,
    tilt: dir * .03 * f.air,
    armLeft: .14 * f.air,
    armRight: .14 * f.air,
    eyes: 1 - .6 * squint,
    joy: squint,
    air: f.air,
  );
}

/// A real dance: a step-hop one way and back, a sway with the arms taking
/// turns and its eyes happy, then a twirl in the air and a cheer.
_Frame _dance(double t, double dir) {
  if (t < 1.1) {
    const hops = [
      _Hop(at: 0, crouch: .14, depth: .88, air: .3, height: .06, travel: .06),
      _Hop(at: .5, crouch: .1, depth: .88, air: .3, height: .06, travel: -.06),
    ];
    final f = _hopFrame(hops, t, dir);
    return _Frame(
      dx: f.dx,
      dy: f.dy,
      squash: f.squash,
      tilt: f.tilt,
      armLeft: .2 * f.air,
      armRight: .2 * f.air,
      air: f.air,
    );
  }
  if (t < 2.75) {
    final u = t - 1.1;
    final env = _window(u, 0, 1.65, .25);
    final p = u * 2 * math.pi * 1.8;
    final s = math.sin(p) * dir;
    return _Frame(
      dx: s * .02 * env,
      dy: -math.sin(p).abs() * .03 * env,
      squash: 1 - (1 - math.sin(p).abs()) * .06 * env,
      tilt: s * .12 * env,
      armLeft: math.max(0, -s) * .45 * env,
      armRight: math.max(0, s) * .45 * env,
      eyes: 1 - .45 * env,
      joy: .8 * env,
    );
  }
  final u = t - 2.75;
  final f = _spinAround(u, dir);
  final cheer = _keys(u, const [(.7, 0), (.95, .3), (1.25, .2), (1.55, 0)]);
  return _Frame(
    dy: f.dy,
    squash: f.squash,
    tilt: f.tilt,
    armLeft: f.armLeft + cheer,
    armRight: f.armRight + cheer,
    spin: f.spin,
    eyes: f.eyes,
    joy: f.joy,
    air: f.air,
  );
}
