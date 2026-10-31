import 'dart:math' as math;

part 'figure_motion/controller.dart';
part 'figure_motion/frame.dart';
part 'figure_motion/reactions.dart';
part 'figure_motion/playful_acts.dart';
part 'figure_motion/interpolation.dart';

/// Everything a friend can act out in its house. The idle ones play on
/// their own now and then; the rest answer the child or the story.
enum Act {
  /// Raises one arm and waves hello (the whole body rocks if it has none).
  wave,

  /// Hop, hop, and one big HOP — landing squashes, arms flying up.
  hop,

  /// A little side-to-side dance, bouncing on the beat.
  wiggle,

  /// Tilts its head, wondering, then perks up as if it had an idea.
  wonder,

  /// 기지개: a long stretch, eyes shut; how it wakes up.
  stretch,

  /// Nodding off; it ends in the sleeping pose.
  doze,

  /// Petted: a ticklish squash and a happy bounce.
  giggle,

  /// Eating a snack held to its mouth: eyes light up, "아~", three
  /// chomps with chewing and puffed cheeks in between, a gulp and a happy
  /// "yum". Its bites land on [eatBites].
  eat,

  /// "No thanks."
  shake,

  /// 빙그르르: crouches, leaps and turns all the way round in the air.
  spin,

  /// 두리번두리번: looks one way, then the other, then back at us. A
  /// side-on friend turns its whole body to look behind it.
  lookAround,

  /// 에취!: "아… 아…" rising in two hitches, then a sneeze that throws it
  /// forward and bounces it back, and a little shake of the head.
  sneeze,

  /// 딸꾹!: three hiccups, each popping it up off the floor, eyes wide.
  hiccup,

  /// 부르르: shakes itself off like a wet puppy, eyes squeezed shut.
  shakeOff,

  /// 하암~: a slow, wide yawn with a stretch, then smacking its lips.
  yawn,

  /// 깔깔: laughs out loud, bouncing on every peal, eyes squeezed happy.
  laugh,

  /// 부끄부끄: blushes, shrinks a little and sways, peeking out happily.
  shy,

  /// 통통: three bouncy little hops in place, each smaller than the last.
  bounce,

  /// A real dance: steps one way and the other, sways with its arms, and
  /// finishes with a twirl and arms up.
  dance,

  /// 킁킁: sniffs the air one way, then the other, as if something smells
  /// good.
  sniff,

  /// 흥얼흥얼: hums a little tune, swaying slowly with its eyes shut.
  hum,

  /// 꽈당!: trips over, lies there a moment, gets up and shakes it off.
  tumble,

  /// 둥실둥실: takes a deep breath (cheeks full) and floats up like a
  /// balloon, bobs dreamily in the air with its eyes shut, then drifts down
  /// and lands softly.
  float,

  /// 말랑말랑: squishes down flat, springs up tall and wobbles like jelly
  /// until it settles.
  jelly,

  /// 까꿍!: curls up small with its eyes shut to hide, trembles with
  /// excitement, then pops up — eyes sparkling, mouth wide.
  peekaboo,

  /// 얼음… 땡!: freezes in a funny pose holding its breath, starts to
  /// tremble from holding still, and is let go with a shake and a smile.
  freeze,

  /// 살금살금: on tiptoe, mouth pressed shut, it creeps off to one side,
  /// checks behind it, creeps back and grins at its own mischief.
  sneak,

  /// 깜짝!: jumps out of its skin — eyes round, mouth an "o" — lands, and
  /// laughs at itself.
  startle,

  /// 두근두근: its body beats "두-근, 두-근" and its cheeks flush deeper on
  /// every beat, eyes sparkling.
  heartbeat,

  /// 어질어질: two quick turns, then it reels round in a little circle with
  /// dazed eyes until it finds its feet.
  dizzy,

  /// 볼 빵빵, 퓨우~: blows its cheeks and body up bigger and bigger, then
  /// lets the air out — whizzing about like a let-go balloon — and sighs.
  puff,

  /// 뒤뚱뒤뚱: waddles on the spot, rocking from foot to foot.
  waddle,

  /// 팡! 팡!: pops up again and again like popcorn, each pop a different
  /// size, eyes wide, until it settles with a grin.
  popcorn,

  /// 야호~!: leans back and calls out with its mouth wide, then listens,
  /// eyes round, for the echo — and beams when it comes back.
  yahoo,

  /// 에헴!: draws itself up tall, chin up and eyes shut, terribly proud.
  proud,

  /// Hops in from off stage (a guest arriving).
  enter,

  /// Hops off stage (a guest going home).
  leave,
}

/// When the bites land in [Act.eat], in seconds from its start. The snack
/// being eaten follows the same beats.
const eatBites = [.62, 1.42, 2.14];
const eatLength = 3.0;

/// The acts a friend picks by itself while nothing else is going on.
const idleActs = [
  Act.hop,
  Act.wave,
  Act.wiggle,
  Act.wonder,
  Act.spin,
  Act.lookAround,
  Act.sneeze,
  Act.hiccup,
  Act.shakeOff,
  Act.yawn,
  Act.shy,
  Act.bounce,
  Act.dance,
  Act.sniff,
  Act.hum,
  Act.tumble,
  Act.float,
  Act.jelly,
  Act.peekaboo,
  Act.freeze,
  Act.sneak,
  Act.startle,
  Act.heartbeat,
  Act.dizzy,
  Act.puff,
  Act.waddle,
  Act.popcorn,
  Act.yahoo,
  Act.proud,
];

/// How a friend answers a pat, picked afresh each time.
const patActs = [...idleActs, Act.giggle, Act.laugh, Act.stretch];

/// How the friend is feeling, from its care and the time: it colours what
/// it does by itself (a sleepy friend yawns rather than dances) and how
/// long it waits in between.
enum Vibe { calm, cheerful, sleepy, hungry }

/// When [Act.puff] lets its air out, each pop of [Act.popcorn], and when
/// the echo of [Act.yahoo] comes back, in seconds from their start.
const puffLetGo = 1.55;
const popcornPops = [.3, .58, .78, 1.02, 1.18, 1.42];
const yahooEcho = 1.75;

/// When [Act.peekaboo] pops out of hiding and [Act.freeze] is let go, in
/// seconds from their start.
const peekabooPop = 1.55;
const freezeLetGo = 1.95;

/// When each hiccup of [Act.hiccup] pops, in seconds from its start.
const hiccupAt = [.4, 1.2, 2.0];

/// The word an act says out loud at [t] seconds in ("에취!"), and how far
/// through saying it (0..1); null when it's quiet.
(String, double)? soundOf(Act act, double t) {
  (String, double)? word(String text, double from, double length) =>
      t >= from && t < from + length ? (text, (t - from) / length) : null;
  return switch (act) {
    Act.sneeze => word('에취!', .95, 1.0),
    Act.shakeOff => word('부르르', .22, 1.1),
    Act.hiccup =>
      hiccupAt.reversed
          .map((at) => word('딸꾹!', at, .75))
          .firstWhere((w) => w != null, orElse: () => null),
    Act.yawn => word('하암~', .45, 1.3),
    Act.laugh => word('깔깔', .2, 1.5),
    Act.sniff => word('킁킁', .35, .8) ?? word('킁킁', 1.45, .8),
    Act.hum => word('♪', .3, 1.1) ?? word('♬', 1.6, 1.1),
    Act.tumble => word('꽈당!', .4, .9),
    Act.float => word('둥실~', .7, 1.5),
    Act.jelly => word('말랑말랑', .5, 1.2),
    Act.peekaboo => word('까꿍!', peekabooPop, .9),
    Act.freeze => word('얼음!', .12, .8) ?? word('땡!', freezeLetGo, .7),
    Act.sneak => word('살금살금', .4, 1.1) ?? word('살금살금', 2.3, 1.1),
    Act.startle => word('깜짝!', .3, .8),
    Act.heartbeat => word('두근두근', .25, 1.7),
    Act.dizzy => word('어질어질', 1.0, 1.6),
    Act.puff => word('퓨우~', puffLetGo, 1.0),
    Act.waddle => word('뒤뚱뒤뚱', .3, 1.9),
    Act.popcorn =>
      popcornPops.reversed
          .map((at) => word('팡!', at, .3))
          .firstWhere((w) => w != null, orElse: () => null),
    Act.yahoo => word('야호~!', .45, .9) ?? word('야호~', yahooEcho, .8),
    Act.proud => word('에헴!', .35, .9),
    _ => null,
  };
}

/// One frame of a friend: where it is and how its body is shaped.
///
/// Distances are in units of the friend's stage size; angles in radians.
/// [armLeft] and [armRight] are positive when the arm is raised (its hand
/// swinging up over the shoulder) and negative when it droops outward.
class FigurePose {
  const FigurePose({
    this.dx = 0,
    this.dy = 0,
    this.scaleX = 1,
    this.scaleY = 1,
    this.tilt = 0,
    this.lean = 0,
    this.armLeft = 0,
    this.armRight = 0,
    this.eyes = 1,
    this.mouth = 0,
    this.cheeks = 0,
    this.look = 0,
    this.turn = 1,
    this.joy = 0,
  });

  final double dx;

  /// Negative is up, off the floor.
  final double dy;
  final double scaleX;
  final double scaleY;

  /// Rocks the whole body about its feet.
  final double tilt;

  /// Shears the top of the body sideways (drag while travelling).
  final double lean;
  final double armLeft;
  final double armRight;

  /// 1 open, 0 shut, above 1 wide with delight.
  final double eyes;

  /// 0 as drawn; up to about 1 wide open, down to -.6 pressed shut.
  final double mouth;

  /// 0 as drawn, 1 puffed out with food.
  final double cheeks;

  /// Where the eyes look: -1 left, 1 right, 0 at us.
  final double look;

  /// 1 as drawn, -1 mirrored; in between while turning around.
  final double turn;

  /// How happy shut eyes are: 0 closed as in sleep (◡), 1 squeezed in a
  /// smile (^^). Only shows while the eyes are shut.
  final double joy;

  /// How high it is off the floor, for its shadow.
  double get lift => math.max(0, -dy);

  static const rest = FigurePose();

  /// Ease from the archive's unposed artwork into life after the hero lands.
  /// Includes the face and arms, not just the outer body transform.
  static FigurePose fromRest(FigurePose pose, double t) => FigurePose(
    dx: pose.dx * t,
    dy: pose.dy * t,
    scaleX: 1 + (pose.scaleX - 1) * t,
    scaleY: 1 + (pose.scaleY - 1) * t,
    tilt: pose.tilt * t,
    lean: pose.lean * t,
    armLeft: pose.armLeft * t,
    armRight: pose.armRight * t,
    eyes: 1 + (pose.eyes - 1) * t,
    mouth: pose.mouth * t,
    cheeks: pose.cheeks * t,
    look: pose.look * t,
    turn: 1 + (pose.turn - 1) * t,
    joy: pose.joy * t,
  );
}
