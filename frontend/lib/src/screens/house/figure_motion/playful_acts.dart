part of '../figure_motion.dart';

/// 킁킁: leans one way and sniffs three times — little bobs, the nose
/// twitching (mouth pressed), eyes half shut — then the other way.
_Frame _sniff(double t, double dir) {
  final side =
      dir *
      _keys(t, const [
        (0, 0),
        (.3, 1),
        (1.15, 1),
        (1.4, -1),
        (2.15, -1),
        (2.4, 0),
      ]);
  var bob = 0.0;
  for (final at in const [.42, .62, .82, 1.52, 1.72, 1.92]) {
    bob += _bump(t, at - .05, at, at + .03);
  }
  return _Frame(
    dx: side * .014,
    dy: .006 * bob,
    squash: 1 - .02 * side.abs() - .025 * bob,
    tilt: side * .06,
    look: side,
    face: side.abs() > .5 ? side.sign : 0,
    eyes: 1 - .35 * side.abs(),
    mouth: -.25 * bob,
    armLeft: .06 * bob,
    armRight: .06 * bob,
  );
}

/// 흥얼흥얼: sways slowly from side to side with its eyes shut in a smile,
/// the mouth opening a little on each note and the arms swaying along.
_Frame _hum(double t, double dir) {
  final env = _window(t, .2, 3.0, .35);
  final p = (t - .2) * 2 * math.pi * .75;
  final s = math.sin(p) * dir;
  final note = .5 + .5 * math.sin((t - .2) * 2 * math.pi * 2.2);
  return _Frame(
    dx: s * .01 * env,
    dy: -.008 * (.5 + .5 * math.cos(p * 2)) * env,
    tilt: s * .08 * env,
    armLeft: (.08 + .1 * math.max(0, -s)) * env,
    armRight: (.08 + .1 * math.max(0, s)) * env,
    eyes: 1 - .8 * env,
    joy: env,
    mouth: (.08 + .22 * note) * env,
  );
}

/// 꽈당!: a stumble (eyes wide), tips over sideways onto the floor with its
/// eyes shut and mouth in an "o", lies there a moment, pushes back up past
/// upright, shakes its head, and gives a little "I'm fine" bounce.
_Frame _tumble(double t, double dir) {
  final shake =
      math.sin((t - 1.6) * 2 * math.pi * 4) * .05 * _window(t, 1.6, 2.15, .08);
  final arms = _keys(t, const [
    (0, 0),
    (.3, .35),
    (.55, -.1),
    (1.15, -.12),
    (1.45, .15),
    (1.8, 0),
  ]);
  return _Frame(
    dx:
        dir *
        _keys(t, const [
          (0, 0),
          (.25, -.008),
          (.5, .03),
          (1.15, .03),
          (1.6, 0),
        ]),
    dy: _keys(t, const [
      (0, 0),
      (.25, -.015),
      (.4, 0),
      (2.25, 0),
      (2.38, -.025),
      (2.55, 0),
    ]),
    squash: _keys(t, const [
      (0, 1),
      (.25, 1.03),
      (.5, .86),
      (.65, .95),
      (1.15, .95),
      (1.4, 1.05),
      (1.6, 1),
      (2.25, .95),
      (2.38, 1.05),
      (2.6, 1),
    ]),
    tilt:
        dir *
            _keys(t, const [
              (0, 0),
              (.25, -.06),
              (.55, .38),
              (1.15, .36),
              (1.45, -.06),
              (1.6, 0),
            ]) +
        shake,
    eyes: _keys(t, const [
      (0, 1),
      (.3, 1.15),
      (.5, .1),
      (1.2, .1),
      (1.45, .6),
      (1.6, 1),
    ]),
    mouth: _keys(t, const [
      (0, 0),
      (.3, .5),
      (.5, .35),
      (1.15, .25),
      (1.45, 0),
    ]),
    armLeft: arms,
    armRight: arms,
    joy: _bump(t, 2.25, 2.35, 2.55),
  );
}

// The five below read on any friend: they are told with the whole body and
// the face (eyes, mouth, cheeks), which a flat generated picture draws from
// its face map. Arms, when a drawing has them, only add to it.

/// 둥실둥실: a deep breath in (cheeks full, a little crouch), then up like a
/// balloon — slowly, eyes shut dreamily — bobbing and swaying in the air
/// while drifting a little, and down again to a soft landing.
_Frame _float(double t, double dir) {
  final aloft = _window(t, 1.0, 2.75, .35);
  final bob = math.sin((t - 1.0) * 2 * math.pi * 1.05) * aloft;
  final sway = math.sin((t - .9) * 2 * math.pi * .55) * aloft;
  final dreamy = _bump(t, .45, .95, 2.55);
  return _Frame(
    dx: dir * .025 * sway,
    dy:
        _keys(t, const [
          (0, 0),
          (.35, .004),
          (1.15, -.16),
          (2.6, -.15),
          (3.3, 0),
        ]) +
        .012 * bob,
    squash:
        _keys(t, const [
          (0, 1),
          (.35, .93),
          (.7, 1.05),
          (2.6, 1.03),
          (3.3, 1),
          (3.42, .94),
          (3.7, 1),
        ]) +
        .015 * bob,
    tilt: dir * .07 * sway,
    armLeft: .3 * aloft + .06 * bob,
    armRight: .3 * aloft - .06 * bob,
    eyes: 1 - .85 * dreamy + .15 * _bump(t, 3.3, 3.36, 3.5),
    joy: dreamy,
    cheeks: _keys(t, const [
      (0, 0),
      (.35, .8),
      (.8, .55),
      (1.3, .25),
      (2.0, 0),
    ]),
    mouth: -.3 * _bump(t, .1, .35, .7),
  );
}

/// 말랑말랑: squishes down flat (eyes squeezed happy), springs up tall and
/// wobbles like jelly — tall-wide, tall-wide, a little less each time — with
/// a soft sway, until it settles.
_Frame _jelly(double t, double dir) {
  final u = math.max(0.0, t - .5);
  final settle = math.exp(-1.9 * u);
  final wobble =
      math.cos(2 * math.pi * 2.2 * u) * settle * _window(t, .45, 2.5, .05);
  final squash = t < .5
      ? _keys(t, const [(0, 1), (.38, .8), (.5, .82)])
      : 1 + .16 * wobble;
  final happy = _window(t, .1, 2.1, .2);
  return _Frame(
    dy: -.02 * _bump(t, .5, .6, .62),
    squash: squash,
    tilt: dir * math.sin(2 * math.pi * 1.1 * u) * .06 * settle,
    armLeft: .25 * wobble,
    armRight: .25 * wobble,
    eyes: 1 - .8 * happy,
    joy: happy,
    cheeks: .5 * happy,
    mouth: .25 * _bump(t, .5, .6, 1.2),
  );
}

/// 까꿍!: glances about, then curls up small to hide, eyes shut (arms over
/// its face if it has them), trembling with excitement — and pops up with
/// a hop, eyes sparkling wide and mouth open, then beams.
_Frame _peekaboo(double t, double dir) {
  const pop = peekabooPop;
  final hidden = _window(t, .55, pop, .12);
  final tremble =
      math.sin(t * 2 * math.pi * 7) * .012 * _window(t, 1.0, pop, .15);
  final surprise = _bump(t, pop - .02, pop + .08, pop + .45);
  final beam = _bump(t, pop + .4, pop + .55, pop + .95);
  return _Frame(
    dx: dir * .008 * _bump(t, .1, .25, .4),
    dy:
        .012 * hidden +
        _keys(t, const [
          (0, 0),
          (pop - .02, 0),
          (pop + .14, -.07),
          (pop + .32, 0),
        ]),
    squash:
        _keys(t, const [
          (0, 1),
          (.55, 1),
          (.75, .8),
          (pop - .04, .8),
          (pop + .1, 1.16),
          (pop + .3, .95),
          (pop + .55, 1.02),
          (pop + .8, 1),
        ]) +
        tremble,
    tilt: dir * (.04 * _bump(t, .1, .25, .4) - .03 * hidden) + tremble,
    look: dir * _bump(t, .1, .2, .4),
    armLeft: .48 * hidden + .4 * surprise,
    armRight: .48 * hidden + .4 * surprise,
    eyes: 1 - .9 * hidden + .28 * surprise - .75 * beam,
    joy: beam,
    mouth: .85 * surprise + .35 * beam,
    cheeks: .6 * surprise + .5 * beam,
  );
}

/// 얼음… 땡!: snaps into a funny pose — leaning over, eyes wide, mouth in an
/// "o", one arm up — and holds it, cheeks puffed with a held breath, until
/// it starts to tremble from holding so still. "땡!" lets it go: a shake,
/// a breath out and a smile.
_Frame _freeze(double t, double dir) {
  const go = freezeLetGo;
  final held = _window(t, .2, go + .05, .1);
  final strain =
      math.sin(t * 2 * math.pi * 11) *
      .012 *
      _keys(t, const [(0, 0), (1.25, 0), (go, 1), (go + .05, 0)]);
  final shake =
      math.sin((t - go) * 2 * math.pi * 4.5) *
      .07 *
      _window(t, go, go + .7, .08);
  final relief = _bump(t, go + .1, go + .25, go + .9);
  return _Frame(
    dx: dir * .012 * held,
    dy: -.012 * _bump(t, .02, .12, .16),
    squash:
        _keys(t, const [
          (0, 1),
          (.1, 1.06),
          (.22, 1.03),
          (go, 1.03),
          (go + .12, .9),
          (go + .35, 1.04),
          (go + .7, 1),
        ]) +
        strain,
    tilt: dir * .15 * held + strain * 1.5 + shake,
    armLeft: dir < 0 ? .5 * held : -.12 * held,
    armRight: dir < 0 ? -.12 * held : .5 * held,
    eyes: 1 + .22 * held - .8 * relief,
    joy: relief,
    mouth:
        .55 * _bump(t, .05, .2, .5) -
        .3 * held * _window(t, .6, go, .2) +
        .3 * relief,
    cheeks: .75 * _window(t, .3, go + .1, .2) + .3 * relief,
  );
}

/// 살금살금: rises on tiptoe with a sly squint and its mouth pressed shut,
/// creeps to one side in little bobbing steps (a side-on friend turns to
/// face where it goes), stops to check behind it, creeps back and grins.
_Frame _sneak(double t, double dir) {
  double steps(double from, double to, double distance) {
    if (t <= from) return 0;
    if (t >= to) return distance;
    // Four steps: each one eases in and out, a pause between.
    final u = (t - from) / (to - from) * 4;
    final i = u.floor();
    return distance * (i + _ease((u - i).clamp(0, 1))) / 4;
  }

  final out = steps(.35, 1.6, .1);
  final back = steps(2.25, 3.5, .1);
  final x = dir * (out - back);
  final walking = _window(t, .35, 1.6, .05) + _window(t, 2.25, 3.5, .05);
  final step = (math.sin((t - .35) * 2 * math.pi * 3.2)).abs() * walking;
  final check = _bump(t, 1.65, 1.8, 2.1);
  final grin = _bump(t, 3.55, 3.7, 4.0);
  return _Frame(
    dx: x,
    dy: -.012 * step,
    squash:
        _keys(t, const [(0, 1), (.3, 1.07), (3.55, 1.07), (3.8, 1)]) -
        .02 * step,
    tilt:
        dir *
        (.035 * math.sin((t - .35) * 2 * math.pi * 1.6) * walking -
            .06 * check),
    face: _window(t, .3, 1.65, .05) > 0
        ? dir
        : _window(t, 2.2, 3.55, .05) > 0
        ? -dir
        : 0,
    look: dir * (check > .3 ? -1 : 0),
    armLeft: .15 * walking,
    armRight: .15 * walking,
    eyes: 1 - .45 * _window(t, .25, 3.55, .2) + .55 * check - .5 * grin,
    joy: grin,
    mouth: -.35 * _window(t, .25, 3.5, .2) + .3 * grin,
    cheeks: .4 * grin,
  );
}

// Eight more, made the same way: the whole body and the face tell them.

/// 깜짝!: a jolt straight up out of stillness — stretched, eyes round,
/// mouth an "o", arms flung — a squashy landing, then a sheepish laugh.
_Frame _startle(double t, double dir) {
  final shock = _bump(t, .26, .32, .85);
  final laugh = _window(t, 1.0, 1.9, .2);
  final peal = .5 + .5 * math.sin((t - 1.0) * 2 * math.pi * 4);
  return _Frame(
    dx: -dir * .012 * shock,
    dy:
        _keys(t, const [(0, 0), (.27, 0), (.38, -.09), (.62, 0)]) -
        .01 * peal * laugh,
    squash: _keys(t, const [
      (0, 1),
      (.27, 1),
      (.34, 1.14),
      (.6, .88),
      (.8, 1.03),
      (1.0, 1),
    ]),
    tilt:
        -dir * .05 * shock +
        .03 * math.sin((t - 1.0) * 2 * math.pi * 2) * laugh,
    armLeft: .45 * shock,
    armRight: .45 * shock,
    eyes: 1 + .28 * shock - .8 * laugh,
    joy: laugh,
    mouth: .8 * shock + (.2 + .2 * peal) * laugh,
    cheeks: .5 * laugh,
    air: _window(t, .3, .6, .05),
  );
}

/// 두근두근: three heartbeats, "두-근" each — a big swell, a little one —
/// cheeks flushing deeper every beat and eyes sparkling, then a happy sigh.
_Frame _heartbeat(double t) {
  var beat = 0.0;
  for (final at in const [.3, .95, 1.6]) {
    beat +=
        _bump(t, at - .04, at, at + .03) +
        .6 * _bump(t, at + .16, at + .2, at + .22);
  }
  final flush = _keys(t, const [
    (0, 0),
    (.3, .3),
    (.95, .6),
    (1.6, .95),
    (2.4, 0),
  ]);
  final sigh = _bump(t, 1.9, 2.05, 2.25);
  return _Frame(
    dy: -.008 * beat,
    squash: 1 + .07 * beat - .04 * sigh,
    armLeft: .12 * beat,
    armRight: .12 * beat,
    eyes: 1 + .2 * _window(t, .2, 1.85, .15) - .7 * sigh,
    joy: sigh,
    cheeks: flush,
    mouth: .15 * _window(t, .2, 1.85, .2),
  );
}

/// 어질어질: two quick turns, then it reels — swaying round in a little
/// circle, eyes half shut and mouth wavering — slowing until it steadies.
_Frame _dizzy(double t, double dir) {
  final u = ((t - .1) / .8).clamp(0.0, 1.0);
  final reel =
      _window(t, .85, 2.7, .25) *
      (1 - .55 * ((t - .85) / 1.85).clamp(0.0, 1.0));
  final p = (t - .85) * 2 * math.pi * 1.3;
  return _Frame(
    dx: math.sin(p) * .022 * reel * dir,
    dy: -.012 * _bump(t, .1, .2, .8) + .006 * (1 - math.cos(2 * p)) * reel,
    squash: _keys(t, const [
      (0, 1),
      (.1, .93),
      (.25, 1.05),
      (.85, 1.02),
      (1.1, .97),
      (2.7, 1),
    ]),
    tilt: math.cos(p) * .1 * reel * dir,
    spin: 4 * math.pi * _ease(u) * dir,
    armLeft: .2 * _bump(t, .1, .25, .8) + .15 * math.sin(p) * reel,
    armRight: .2 * _bump(t, .1, .25, .8) - .15 * math.sin(p) * reel,
    eyes: 1 - .55 * reel - .3 * _bump(t, .15, .25, .8),
    mouth: (-.25 + .15 * math.sin(p * 2)) * reel,
    look: math.sin(p) * reel,
  );
}

/// 볼 빵빵, 퓨우~: puffs its cheeks and body up — wider and shorter, eyes
/// squeezed with the effort, trembling at the end — then lets go: mouth
/// open, it whizzes about like a let-go balloon, shrinks back and sighs.
_Frame _puff(double t, double dir) {
  const go = puffLetGo;
  final full = _keys(t, const [
    (0, 0),
    (.25, .2),
    (.7, .55),
    (go - .1, 1),
    (go, 1),
    (go + .5, 0),
  ]);
  final strain = math.sin(t * 2 * math.pi * 10) * .01 * _window(t, 1.1, go, .1);
  final whizz =
      _window(t, go, go + .9, .08) * (1 - ((t - go) / .9).clamp(0.0, 1.0));
  final w = (t - go) * 2 * math.pi * 5;
  return _Frame(
    dx: math.sin(w) * .02 * whizz * dir,
    dy: -.03 * whizz * (.5 + .5 * math.sin(w * .5)),
    squash: 1 - .12 * full + strain + .05 * math.sin(w) * whizz,
    tilt: math.sin(w + .7) * .09 * whizz * dir,
    armLeft: .2 * full + .3 * whizz,
    armRight: .2 * full + .3 * whizz,
    eyes:
        1 -
        .55 * full * _window(t, .5, go + .05, .2) +
        .15 * whizz -
        .6 * _bump(t, go + 1.05, go + 1.2, go + 1.4),
    joy: _bump(t, go + 1.05, go + 1.2, go + 1.4),
    cheeks: 1.25 * full,
    mouth: -.45 * full * _window(t, .1, go, .1) + .6 * whizz,
  );
}

/// 뒤뚱뒤뚱: rocks from foot to foot on the spot — leaning onto one side,
/// a little bob as it shifts, onto the other — with a contented smile.
_Frame _waddle(double t) {
  final env = _window(t, .2, 2.4, .25);
  final p = (t - .2) * 2 * math.pi * 1.4;
  final rock = math.sin(p);
  return _Frame(
    dx: rock * .014 * env,
    dy: -.016 * (1 - math.cos(2 * p)) / 2 * env,
    squash: 1 + .025 * env - .02 * (1 - math.cos(2 * p)) / 2 * env,
    tilt: rock * .12 * env,
    armLeft: (.1 + .12 * math.max(0, rock)) * env,
    armRight: (.1 + .12 * math.max(0, -rock)) * env,
    eyes: 1 - .5 * env,
    joy: .8 * env,
    mouth: .12 * env,
  );
}

/// 팡! 팡!: pops straight up again and again, each pop a different height,
/// tilting this way and that, eyes wide and mouth round — and a grin once
/// the popping stops.
_Frame _popcorn(double t) {
  const heights = [.05, .08, .04, .09, .035, .06];
  // Pops overlap a little; each starts and ends at rest, so they add up.
  var dy = 0.0, squash = 1.0, tilt = 0.0, air = 0.0;
  for (final (i, at) in popcornPops.indexed) {
    if (t < at - .06 || t > at + .22) continue;
    dy += _keys(t, [
      (at - .06, 0),
      (at - .02, .004),
      (at + .08, -heights[i]),
      (at + .2, 0),
    ]);
    squash +=
        _keys(t, [
          (at - .06, 1),
          (at - .02, .9),
          (at + .04, 1.1),
          (at + .2, .94),
          (at + .22, 1),
        ]) -
        1;
    tilt += (i.isEven ? 1 : -1) * .06 * _bump(t, at - .02, at + .08, at + .12);
    air = math.max(air, _window(t, at, at + .18, .03));
  }
  final popping = _window(t, .2, 1.65, .1);
  final grin = _bump(t, 1.7, 1.85, 2.1);
  return _Frame(
    dy: dy,
    squash: squash,
    tilt: tilt,
    armLeft: .3 * air,
    armRight: .3 * air,
    eyes: 1 + .22 * popping - .7 * grin,
    joy: grin,
    mouth: .45 * popping + .25 * grin,
    cheeks: .4 * grin,
    air: air,
  );
}

/// 야호~!: leans back and calls out, mouth wide and arms up; then listens
/// (eyes round, leaning toward where it called), and when the echo comes
/// back it gives a delighted bounce. A side-on friend faces where it calls.
_Frame _yahoo(double t, double dir) {
  final call = _window(t, .35, 1.35, .15);
  final listen = _window(t, 1.4, yahooEcho + .55, .15);
  final glee = _bump(t, yahooEcho + .55, yahooEcho + .7, yahooEcho + 1.0);
  return _Frame(
    dx: dir * .012 * listen,
    dy:
        -.012 * _bump(t, .25, .4, 1.3) -
        .04 * _bump(t, yahooEcho + .55, yahooEcho + .65, yahooEcho + .7),
    squash:
        _keys(t, const [
          (0, 1),
          (.25, .93),
          (.45, 1.1),
          (1.3, 1.08),
          (1.5, 1),
        ]) -
        .05 * _bump(t, yahooEcho + .45, yahooEcho + .55, yahooEcho + .57),
    tilt: dir * (-.06 * call + .07 * listen),
    face: call > .3 || listen > .3 ? dir : 0,
    look: dir * listen,
    armLeft: .45 * call + .3 * glee,
    armRight: .45 * call + .3 * glee,
    eyes: 1 - .45 * call + .25 * listen - .7 * glee,
    joy: glee,
    mouth: 1.0 * call + .35 * glee,
    cheeks: .45 * call + .55 * glee,
  );
}

/// 에헴!: draws itself up tall — chin up, eyes shut, cheeks pink, arms out
/// as if on its hips — holds it a moment, gives a little nod and lets go.
_Frame _proud(double t, double dir) {
  final pose = _window(t, .2, 2.0, .25);
  final nod = _bump(t, 1.55, 1.65, 1.75);
  return _Frame(
    dy: -.012 * pose + .01 * nod,
    squash: 1 + .1 * pose - .06 * nod + .02 * _bump(t, .3, .38, .45),
    tilt: -dir * .06 * pose,
    armLeft: -.18 * pose,
    armRight: -.18 * pose,
    eyes: 1 - .85 * pose,
    joy: pose,
    cheeks: .55 * pose,
    mouth: .3 * _bump(t, .32, .4, .9) - .2 * pose * _window(t, 1.0, 2.0, .2),
  );
}
