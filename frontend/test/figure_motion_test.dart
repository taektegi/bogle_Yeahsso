import 'dart:math' as math;

import 'package:bogle_app/src/screens/house/figure_motion.dart';
import 'package:bogle_app/src/screens/house/face_map.dart';
import 'package:bogle_app/src/screens/house/figure_rig.dart';
import 'package:bogle_app/src/screens/house/house_widgets.dart';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Plays [act] at 60 fps and returns every frame's pose.
List<FigurePose> film(Act act, {double travel = 1.5, double direction = 1}) {
  final motion = FigureMotion(random: math.Random(1), hasArms: true)
    ..advance(.5, idle: false)
    ..play(act, travel: travel, direction: direction);
  return [
    for (var i = 0; i < (actLength(act, travel) + 1.5) * 60; i++)
      (motion..advance(1 / 60, idle: false)).pose,
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final act in Act.values) {
    test('$act moves smoothly and comes back to rest', () {
      final frames = film(act);
      for (final (i, p) in frames.indexed.skip(1)) {
        final before = frames[i - 1];
        for (final v in [p.dx, p.dy, p.scaleX, p.scaleY, p.tilt, p.armLeft]) {
          expect(v.isFinite, isTrue);
        }
        // No frame jumps: a hop moves at most a few percent per frame.
        if (act != Act.enter && act != Act.leave) {
          expect((p.dx - before.dx).abs(), lessThan(.03), reason: '$i');
        }
        expect((p.dy - before.dy).abs(), lessThan(.04), reason: '$i');
        expect((p.tilt - before.tilt).abs(), lessThan(.06), reason: '$i');
        // Soft, not rubber: it never squashes flat or stretches thin.
        expect(p.scaleY, inInclusiveRange(.7, 1.3), reason: '$i');
      }
      final end = frames.last;
      if (act != Act.leave) expect(end.dx.abs(), lessThan(.005));
      expect(end.dy.abs(), lessThan(.005));
      expect(end.tilt.abs(), lessThan(.02));
    });
  }

  test('a hop leaves the floor and lands squashed', () {
    final frames = film(Act.hop);
    final highest = frames.map((p) => p.dy).reduce(math.min);
    expect(highest, lessThan(-.2));
    expect(frames.map((p) => p.scaleY).reduce(math.min), lessThan(.9));
    expect(frames.map((p) => p.scaleY).reduce(math.max), greaterThan(1.08));
  });

  test('waving lifts one arm and keeps the other down', () {
    final frames = film(Act.wave);
    final right = frames.map((p) => p.armRight);
    final left = frames.map((p) => p.armLeft);
    expect(right.reduce(math.max), greaterThan(.35));
    expect(right.reduce(math.min), lessThan(-.05));
    expect(left.reduce(math.max), lessThan(.2));
  });

  test('a guest enters from off stage and leaves the same way', () {
    final entering = film(Act.enter, travel: 2, direction: -1);
    expect(entering.first.dx, closeTo(2, .05));
    expect(entering.last.dx, closeTo(0, .005));
    final leaving = film(Act.leave, travel: 2);
    expect(leaving.last.dx, closeTo(2, .005));
  });

  test('cutting an act off mid-air carries on from where the body was', () {
    final motion = FigureMotion(random: math.Random(1), hasArms: true)
      ..advance(.5, idle: false)
      ..play(Act.hop);
    for (var i = 0; i < 87; i++) {
      motion.advance(1 / 60, idle: false);
    }
    final before = motion.pose;
    expect(before.dy, lessThan(-.15));
    motion
      ..play(Act.wave)
      ..advance(1 / 60, idle: false);
    expect((motion.pose.dy - before.dy).abs(), lessThan(.03));
  });

  test('idle friends pick something to do by themselves', () {
    final motion = FigureMotion(random: math.Random(2));
    final seen = <Act>{};
    // Long enough for the rarest of the 29 idle acts to come up.
    for (var i = 0; i < 60 * 1500; i++) {
      motion.advance(1 / 60);
      if (motion.acting case final act?) seen.add(act);
    }
    expect(seen, containsAll(idleActs));
  });

  test('asleep it stays put with its eyes shut', () {
    final motion = FigureMotion(random: math.Random(3), hasArms: true);
    for (var i = 0; i < 60 * 30; i++) {
      motion.advance(1 / 60, asleep: true);
      expect(motion.acting, isNull);
    }
    expect(motion.pose.eyes, lessThan(.2));
    expect(motion.pose.tilt, closeTo(-.08, .02));
  });

  test('뭉글이 is rigged from the part names in its drawing', () async {
    for (final asset in [
      'assets/figma/character_card.svg',
      'assets/figma/character_friend.svg',
    ]) {
      final rig = (await rigFor(asset))!;
      expect(rig.layers.keys, [
        RigPart.eyes,
        RigPart.mouth,
        RigPart.armRight,
        RigPart.armLeft,
        RigPart.cheeks,
      ]);
      expect(rig.hasArms && rig.hasFace, isTrue);
      final left = rig.layers[RigPart.armLeft]!;
      final right = rig.layers[RigPart.armRight]!;
      // Shoulders mirror each other and sit on the arms.
      expect(left.pivot.dx + right.pivot.dx, closeTo(1, .01));
      expect(left.bounds.inflate(.02).contains(left.pivot), isTrue);
      // The mouth opens from its top lip, below the eyes.
      final mouth = rig.layers[RigPart.mouth]!;
      expect(mouth.pivot.dy, closeTo(mouth.bounds.top, .001));
      expect(mouth.bounds.top, greaterThan(rig.layers[RigPart.eyes]!.pivot.dy));
      // The body no longer draws the parts that now move.
      expect(rig.body, isNot(contains('bogle-mouth')));
    }
    expect(await rigFor('assets/figma/dduchi.png'), isNull);
  });

  test('any drawing that names its parts gets them, however drawn', () async {
    const svg = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
  <circle cx="50" cy="60" r="30" fill="#9cf"/>
  <g id="bogle-eyes"><circle cx="40" cy="55" r="3"/><circle cx="60" cy="55" r="3"/></g>
  <path id="bogle-mouth" d="M42 68 H58 Q50 78 42 68 Z" fill="#e55"/>
  <rect id="bogle-arm-right" x="78" y="40" width="8" height="30" fill="#9cf"/>
</svg>""";
    final rig = (await FigureRig.parse(svg))!;
    expect(rig.layers.keys, [RigPart.eyes, RigPart.mouth, RigPart.armRight]);
    expect(rig.hasArms, isTrue);
    // No shoulder given: the arm turns about its lowest inner corner.
    final arm = rig.layers[RigPart.armRight]!;
    expect(arm.pivot.dx, closeTo(.78, .02));
    expect(arm.pivot.dy, closeTo(.655, .03));
    expect(rig.layers[RigPart.eyes]!.pivot.dy, closeTo(.55, .02));
    // A drawing with no named parts moves as a whole.
    expect(
      await FigureRig.parse(
        '<svg viewBox="0 0 10 10"><rect width="5" height="5"/></svg>',
      ),
      isNull,
    );
    expect(await FigureRig.parse('not svg'), isNull);
  });

  test('eating opens wide, chomps on the beats, chews and swallows', () {
    final motion = FigureMotion(random: math.Random(5), hasArms: true)
      ..advance(.5, idle: false)
      ..play(Act.eat);
    final mouth = <double>[], cheeks = <double>[], eyes = <double>[];
    for (var i = 0; i < (eatLength + .5) * 120; i++) {
      motion.advance(1 / 120, idle: false);
      mouth.add(motion.pose.mouth);
      cheeks.add(motion.pose.cheeks);
      eyes.add(motion.pose.eyes);
    }
    double at(List<double> v, double t) => v[(t * 120).round() - 1];
    for (final bite in eatBites) {
      expect(at(mouth, bite - .06), greaterThan(.7), reason: 'wide before');
      expect(at(mouth, bite + .06), lessThan(-.2), reason: 'shut on $bite');
    }
    // Chewing: the mouth works open and shut, cheeks puffed, eyes squeezed.
    final chewing = mouth.sublist(
      ((eatBites[0] + .1) * 120).round(),
      ((eatBites[1] - .35) * 120).round(),
    );
    expect(
      chewing.reduce(math.max) - chewing.reduce(math.min),
      greaterThan(.2),
    );
    expect(at(cheeks, 1.0), greaterThan(.7));
    expect(at(eyes, 1.0), lessThan(.7));
    // Spots the snack wide-eyed; ends with a "yum" and back to itself.
    expect(eyes.take(40).reduce(math.max), greaterThan(1.1));
    expect(at(mouth, 2.8), greaterThan(.2));
    expect(mouth.last.abs(), lessThan(.05));
    expect(cheeks.last, lessThan(.05));
  });

  test('a side-on guest turns around to face where it hops', () {
    final motion = FigureMotion(random: math.Random(4), facing: -1)
      ..play(Act.enter, travel: 2);
    for (var i = 0; i < 60; i++) {
      motion.advance(1 / 60, idle: false);
    }
    // 뚜치 faces left; hopping right it is drawn mirrored.
    expect(motion.pose.turn, lessThan(-.9));
  });

  test('spinning turns the drawing all the way round and back', () {
    final turns = film(Act.spin).map((p) => p.turn).toList();
    expect(turns.reduce(math.min), lessThan(-.9));
    expect(turns.last, closeTo(1, .02));
  });

  test('looking around moves the eyes one way, then the other', () {
    final looks = film(Act.lookAround).map((p) => p.look);
    expect(looks.reduce(math.max), greaterThan(.8));
    expect(looks.reduce(math.min), lessThan(-.8));
  });

  test('sneezes, hiccups and shaking off say so out loud', () {
    expect(soundOf(Act.sneeze, .5), isNull);
    expect(soundOf(Act.sneeze, 1.2)?.$1, '에취!');
    for (final at in hiccupAt) {
      expect(soundOf(Act.hiccup, at + .1)?.$1, '딸꾹!');
    }
    expect(soundOf(Act.hiccup, .2), isNull);
    expect(soundOf(Act.shakeOff, .6)?.$1, '부르르');
    expect(soundOf(Act.hop, .6), isNull);
  });

  test('flat pictures bring a face map; the house knows their faces', () async {
    final nemorin = (await faceMapFor('assets/figma/nemorin.png'))!;
    expect(nemorin.facing, -1);
    expect(nemorin.eyes, hasLength(1));
    // The eyelid takes the colour of the skin around the eye: yellow.
    final skin = nemorin.skins.single;
    expect(skin.r, greaterThan(.9));
    expect(skin.b, lessThan(.5));
    final dduchi = (await faceMapFor('assets/figma/dduchi.png'))!;
    expect(dduchi.facing, -1);
    expect(await faceMapFor('assets/figma/archive_nemorin.png'), isNull);
    expect(await faceMapFor('assets/figma/character_card.svg'), isNull);

    // 네모린's mouth is at the tip of its snout: top left, not the body.
    final anchors = await anchorsFor('assets/figma/nemorin.png');
    expect(anchors.facing, -1);
    expect(anchors.mouth!.center.dx, lessThan(.15));
    expect(anchors.mouth!.center.dy, lessThan(.3));
    expect(
      (await anchorsFor('assets/figma/character_card.svg')).mouth,
      isNotNull,
    );
  });

  test('a face map is read leniently', () {
    expect(FaceMap.fromJson('nope'), isNull);
    expect(
      FaceMap.fromJson({
        'size': [0, 10],
      }),
      isNull,
    );
    final face = FaceMap.fromJson({
      'size': [200, 100],
      'facing': 'right',
      'eyes': [
        [50, 40, 6],
        ['bad'],
      ],
      'mouth': [100, 70, 20, 8],
    })!;
    expect(face.facing, 1);
    expect(face.eyes, hasLength(1));
    expect(face.fraction(face.mouth!).center, const Offset(.5, .7));
    expect(face.head, isNull);
  });

  group('more to do', () {
    double most(List<FigurePose> f, double Function(FigurePose) v) =>
        f.map(v).reduce(math.max);
    double least(List<FigurePose> f, double Function(FigurePose) v) =>
        f.map(v).reduce(math.min);

    test('a yawn opens wide with the eyes shut, then smacks its lips', () {
      final f = film(Act.yawn);
      expect(most(f, (p) => p.mouth), greaterThan(1));
      expect(least(f, (p) => p.eyes), lessThan(.2));
      expect(least(f, (p) => p.mouth), lessThan(-.15));
    });

    test('a laugh peals again and again, eyes smiling and cheeks pink', () {
      final f = film(Act.laugh);
      var peals = 0;
      for (var i = 1; i < f.length - 1; i++) {
        final m = f[i].mouth;
        if (m > .5 && m > f[i - 1].mouth && m >= f[i + 1].mouth) peals++;
      }
      expect(peals, greaterThanOrEqualTo(4));
      expect(most(f, (p) => p.joy), greaterThan(.9));
      expect(most(f, (p) => p.cheeks), greaterThan(.5));
    });

    test('shy: blushes, smiles with its eyes shut and turns aside', () {
      final f = film(Act.shy, direction: -1);
      expect(most(f, (p) => p.cheeks), greaterThan(.5));
      expect(most(f, (p) => p.joy), greaterThan(.7));
      expect(least(f, (p) => p.tilt), lessThan(-.04));
    });

    test('a bounce is three hops in place, each lower than the last', () {
      final f = film(Act.bounce);
      final tops = <double>[];
      var top = 0.0;
      for (final p in f) {
        if (p.dy < -.01) {
          top = math.min(top, p.dy);
        } else if (top < 0) {
          tops.add(top);
          top = 0;
        }
      }
      expect(tops, hasLength(3));
      expect(tops[0], lessThan(tops[1]));
      expect(tops[1], lessThan(tops[2]));
    });

    test('a dance steps, sways with its arms in turn and twirls', () {
      final f = film(Act.dance);
      expect(most(f, (p) => p.dx.abs()), greaterThan(.03));
      expect(most(f, (p) => p.armLeft), greaterThan(.3));
      expect(most(f, (p) => p.armRight), greaterThan(.3));
      expect(least(f, (p) => p.turn), lessThan(-.9));
    });

    test('sniffing leans and looks one way, then the other', () {
      final f = film(Act.sniff);
      expect(most(f, (p) => p.look), greaterThan(.8));
      expect(least(f, (p) => p.look), lessThan(-.8));
      expect(least(f, (p) => p.mouth), lessThan(-.12));
    });

    test('humming shuts the eyes in a smile and moves the mouth', () {
      final f = film(Act.hum);
      expect(most(f, (p) => p.joy), greaterThan(.9));
      expect(least(f, (p) => p.eyes), lessThan(.35));
      expect(most(f, (p) => p.mouth), greaterThan(.2));
    });

    test('a tumble tips well over, then it gets back up', () {
      final f = film(Act.tumble);
      expect(most(f, (p) => p.tilt), greaterThan(.25));
      expect(f.last.tilt.abs(), lessThan(.02));
    });

    test('the new acts say so out loud', () {
      expect(soundOf(Act.yawn, 1.0)?.$1, '하암~');
      expect(soundOf(Act.laugh, 1.0)?.$1, '깔깔');
      expect(soundOf(Act.sniff, .5)?.$1, '킁킁');
      expect(soundOf(Act.sniff, 1.6)?.$1, '킁킁');
      expect(soundOf(Act.hum, .5)?.$1, '♪');
      expect(soundOf(Act.hum, 2.0)?.$1, '♬');
      expect(soundOf(Act.tumble, .6)?.$1, '꽈당!');
      expect(soundOf(Act.shy, 1.0), isNull);
    });

    test('happy moments shut the eyes in a smile, sleep does not', () {
      expect(most(film(Act.hop), (p) => p.joy), greaterThan(.5));
      expect(most(film(Act.giggle), (p) => p.joy), greaterThan(.5));
      expect(most(film(Act.doze), (p) => p.joy), lessThan(.05));
      expect(most(film(Act.sneeze), (p) => p.joy), lessThan(.05));
    });
  });

  group('five more, for every friend', () {
    /// Frames of [act] for a friend without arms — a generated picture —
    /// looking [facing] (-1 left, 1 right, 0 at us).
    List<FigurePose> flat(Act act, {double direction = 1, double facing = 0}) {
      final motion = FigureMotion(random: math.Random(1), facing: facing)
        ..advance(.5, idle: false)
        ..play(act, direction: direction);
      return [
        for (var i = 0; i < (actLength(act) + 1.5) * 60; i++)
          (motion..advance(1 / 60, idle: false)).pose,
      ];
    }

    FigurePose at(List<FigurePose> frames, double seconds) =>
        frames[(seconds * 60).round()];
    double top(Iterable<double> v) => v.reduce(math.max);
    double bottom(Iterable<double> v) => v.reduce(math.min);

    test('float rises like a balloon, dreams in the air and lands softly', () {
      final f = flat(Act.float);
      expect(bottom(f.map((p) => p.dy)), lessThan(-.13));
      final aloft = at(f, 1.8);
      expect(aloft.dy, lessThan(-.12));
      expect(aloft.eyes, lessThan(.35));
      expect(aloft.joy, greaterThan(.5));
      expect(top(f.take(60).map((p) => p.cheeks)), greaterThan(.5));
      expect(f.last.dy.abs(), lessThan(.005));
    });

    test('jelly squishes, springs up tall and wobbles a few times', () {
      final f = flat(Act.jelly);
      expect(bottom(f.map((p) => p.scaleY)), lessThan(.86));
      var peaks = 0;
      for (var i = 1; i < f.length - 1; i++) {
        final y = f[i].scaleY;
        if (y > 1.04 && y >= f[i - 1].scaleY && y > f[i + 1].scaleY) peaks++;
      }
      expect(peaks, greaterThanOrEqualTo(2));
      expect(top(f.map((p) => p.joy)), greaterThan(.5));
    });

    test('peekaboo hides small with its eyes shut, then pops out wide', () {
      final f = flat(Act.peekaboo);
      final hiding = at(f, 1.25);
      expect(hiding.scaleY, lessThan(.9));
      expect(hiding.eyes, lessThan(.3));
      final pop = at(f, peekabooPop + .1);
      expect(pop.eyes, greaterThan(1.1), reason: 'sparkling');
      expect(pop.mouth, greaterThan(.5));
      expect(bottom(f.map((p) => p.dy)), lessThan(-.04));
      expect(top(f.map((p) => p.joy)), greaterThan(.5));
    });

    test('freeze holds a pose still, trembles, and is let go', () {
      final f = flat(Act.freeze, direction: -1);
      final held = f.sublist(40, 75); // 0.67–1.25 s
      final tilts = held.map((p) => p.tilt);
      expect(bottom(tilts), lessThan(-.1), reason: 'leaning over');
      expect(top(tilts) - bottom(tilts), lessThan(.025), reason: 'still');
      expect(bottom(held.map((p) => p.cheeks)), greaterThan(.4));
      expect(at(f, 1.0).eyes, greaterThan(1.1));
      expect(at(f, freezeLetGo + .3).joy, greaterThan(.5));
    });

    test('sneak creeps off on tiptoe and comes back; side-on it turns', () {
      final front = flat(Act.sneak);
      // A little farther or nearer each time it plays.
      expect(at(front, 1.65).dx, closeTo(.1, .02));
      expect(at(front, 1.0).mouth, lessThan(-.2), reason: 'mouth pressed');
      expect(at(front, 1.0).scaleY, greaterThan(1.03), reason: 'tiptoe');
      expect(bottom(front.map((p) => p.turn)), greaterThan(.99));
      expect(front.last.dx.abs(), lessThan(.005));

      // 티노 looks right; creeping left it turns round, coming back it
      // turns to face the way it goes again.
      final tino = flat(Act.sneak, direction: -1, facing: 1);
      expect(at(tino, 1.65).dx, closeTo(-.1, .02));
      expect(at(tino, 1.2).turn, lessThan(-.9));
      expect(at(tino, 3.2).turn, greaterThan(.9));
    });

    test('they say so out loud', () {
      expect(soundOf(Act.float, 1.0)?.$1, '둥실~');
      expect(soundOf(Act.jelly, .8)?.$1, '말랑말랑');
      expect(soundOf(Act.peekaboo, peekabooPop + .2)?.$1, '까꿍!');
      expect(soundOf(Act.peekaboo, 1.0), isNull, reason: 'hiding quietly');
      expect(soundOf(Act.freeze, .3)?.$1, '얼음!');
      expect(soundOf(Act.freeze, freezeLetGo + .2)?.$1, '땡!');
      expect(soundOf(Act.sneak, .6)?.$1, '살금살금');
    });

    test('a sleepy friend may float but does not play jelly, peekaboo or '
        'freeze', () {
      final motion = FigureMotion(random: math.Random(3))..vibe = Vibe.sleepy;
      final seen = <Act>{};
      for (var i = 0; i < 60 * 900; i++) {
        motion.advance(1 / 60);
        if (motion.acting case final act?) seen.add(act);
      }
      expect(seen, contains(Act.float));
      expect(seen.intersection({Act.jelly, Act.peekaboo, Act.freeze}), isEmpty);
    });
  });

  group('eight more, for every friend', () {
    List<FigurePose> flat(Act act, {double direction = 1, double facing = 0}) {
      final motion = FigureMotion(random: math.Random(1), facing: facing)
        ..advance(.5, idle: false)
        ..play(act, direction: direction);
      return [
        for (var i = 0; i < (actLength(act) + 1.5) * 60; i++)
          (motion..advance(1 / 60, idle: false)).pose,
      ];
    }

    FigurePose at(List<FigurePose> frames, double seconds) =>
        frames[(seconds * 60).round()];
    double top(Iterable<double> v) => v.reduce(math.max);
    double bottom(Iterable<double> v) => v.reduce(math.min);
    int peaks(List<double> v, double above) {
      var n = 0;
      for (var i = 1; i < v.length - 1; i++) {
        if (v[i] > above && v[i] >= v[i - 1] && v[i] > v[i + 1]) n++;
      }
      return n;
    }

    test('startle jumps with round eyes and an "o", then laughs', () {
      final f = flat(Act.startle);
      expect(bottom(f.map((p) => p.dy)), lessThan(-.06));
      final jolt = at(f, .4);
      expect(jolt.eyes, greaterThan(1.15));
      expect(jolt.mouth, greaterThan(.5));
      expect(top(f.skip(60).map((p) => p.joy)), greaterThan(.5));
    });

    test('heartbeat beats three times, flushing deeper each time', () {
      final f = flat(Act.heartbeat);
      expect(
        peaks([for (final p in f) p.scaleY], 1.035),
        greaterThanOrEqualTo(3),
      );
      expect(at(f, 1.65).cheeks, greaterThan(at(f, .35).cheeks + .3));
      expect(at(f, 1.0).eyes, greaterThan(1.1));
    });

    test('dizzy turns twice, then reels with dazed eyes', () {
      final f = flat(Act.dizzy);
      var flips = 0;
      for (var i = 1; i < f.length; i++) {
        if (f[i].turn.sign != f[i - 1].turn.sign) flips++;
      }
      expect(flips, greaterThanOrEqualTo(4), reason: 'two whole turns');
      final reeling = f.sublist(66, 120); // 1.1–2.0 s
      expect(top(reeling.map((p) => p.dx)), greaterThan(.01));
      expect(bottom(reeling.map((p) => p.dx)), lessThan(-.01));
      expect(at(f, 1.4).eyes, lessThan(.65));
    });

    test('puff blows up wide with full cheeks, then lets the air out', () {
      final f = flat(Act.puff);
      final full = at(f, puffLetGo - .05);
      expect(full.cheeks, greaterThan(1.0));
      expect(full.scaleX, greaterThan(1.06), reason: 'wider');
      expect(top(f.map((p) => p.mouth)), greaterThan(.4), reason: '퓨우~');
      expect(f.last.cheeks, lessThan(.05));
    });

    test('waddle rocks from side to side, smiling', () {
      final f = flat(Act.waddle);
      var sides = 0;
      var last = 0.0;
      for (final p in f) {
        if (p.tilt.abs() > .06 && p.tilt.sign != last) {
          sides++;
          last = p.tilt.sign;
        }
      }
      expect(sides, greaterThanOrEqualTo(4));
      expect(at(f, 1.3).joy, greaterThan(.5));
    });

    test('popcorn pops up again and again', () {
      final f = flat(Act.popcorn);
      expect(peaks([for (final p in f) -p.dy], .02), greaterThanOrEqualTo(5));
      expect(at(f, .9).eyes, greaterThan(1.1));
      expect(top(f.map((p) => p.joy)), greaterThan(.5));
    });

    test('yahoo calls wide, listens for the echo and beams; side-on it '
        'faces where it calls', () {
      final f = flat(Act.yahoo);
      expect(at(f, .9).mouth, greaterThan(.8));
      expect(at(f, yahooEcho).eyes, greaterThan(1.1), reason: 'listening');
      expect(top(f.map((p) => p.joy)), greaterThan(.5));
      final tino = flat(Act.yahoo, direction: -1, facing: 1);
      expect(at(tino, 1.0).turn, lessThan(-.9));
      expect(tino.last.turn, greaterThan(.95));
    });

    test('proud draws itself up tall with its eyes shut', () {
      final f = flat(Act.proud);
      expect(at(f, 1.0).scaleY, greaterThan(1.07));
      expect(at(f, 1.0).joy, greaterThan(.8));
      expect(at(f, 1.0).eyes, lessThan(.3));
    });

    test('they say so out loud', () {
      expect(soundOf(Act.startle, .5)?.$1, '깜짝!');
      expect(soundOf(Act.heartbeat, 1.0)?.$1, '두근두근');
      expect(soundOf(Act.dizzy, 1.5)?.$1, '어질어질');
      expect(soundOf(Act.puff, puffLetGo + .3)?.$1, '퓨우~');
      expect(soundOf(Act.waddle, 1.0)?.$1, '뒤뚱뒤뚱');
      for (final at in popcornPops) {
        expect(soundOf(Act.popcorn, at + .1)?.$1, '팡!');
      }
      expect(soundOf(Act.yahoo, .8)?.$1, '야호~!');
      expect(soundOf(Act.yahoo, yahooEcho + .3)?.$1, '야호~');
      expect(soundOf(Act.proud, .6)?.$1, '에헴!');
    });
  });

  test('the same act is a little different each time it plays', () {
    final motion = FigureMotion(random: math.Random(5))
      ..advance(.5, idle: false);
    final heights = <double>[];
    for (var k = 0; k < 5; k++) {
      motion.play(Act.hop);
      var top = 0.0;
      for (var i = 0; i < 3.5 * 60; i++) {
        motion.advance(1 / 60, idle: false);
        top = math.min(top, motion.pose.dy);
      }
      heights.add(top);
    }
    expect(
      heights.reduce(math.max) - heights.reduce(math.min),
      greaterThan(.01),
    );
    // …but always a real hop.
    expect(heights.reduce(math.max), lessThan(-.2));
  });

  /// How often each act is picked by itself over [seconds].
  Map<Act, int> picks(Vibe vibe, {int seconds = 900}) {
    final motion = FigureMotion(random: math.Random(4))..vibe = vibe;
    final counts = <Act, int>{};
    Act? before;
    for (var i = 0; i < seconds * 60; i++) {
      motion.advance(1 / 60);
      final now = motion.acting;
      if (now != null && before == null) counts[now] = (counts[now] ?? 0) + 1;
      before = now;
    }
    return counts;
  }

  test('a sleepy friend yawns and never dances; a hungry one sniffs', () {
    const lively = [
      Act.hop,
      Act.wiggle,
      Act.spin,
      Act.bounce,
      Act.dance,
      Act.hiccup,
      Act.tumble,
    ];
    final sleepy = picks(Vibe.sleepy);
    for (final act in lively) {
      expect(sleepy[act], isNull, reason: '$act');
    }
    final mostSleepy = sleepy.entries.reduce(
      (a, b) => a.value >= b.value ? a : b,
    );
    expect(mostSleepy.key, Act.yawn);

    final hungry = picks(Vibe.hungry);
    final mostHungry = hungry.entries.reduce(
      (a, b) => a.value >= b.value ? a : b,
    );
    expect(mostHungry.key, Act.sniff);

    int livelyShare(Map<Act, int> p) =>
        lively.fold(0, (sum, act) => sum + (p[act] ?? 0)) *
        100 ~/
        p.values.fold(0, (a, b) => a + b);
    expect(
      livelyShare(picks(Vibe.cheerful)),
      greaterThan(livelyShare(picks(Vibe.calm))),
    );
  });

  test('터치 동작은 전체를 사용한 뒤 다시 섞으며 경계에서도 반복하지 않는다', () {
    final motion = FigureMotion(random: math.Random(6));
    final answers = [
      for (var i = 0; i < patActs.length * 4; i++) motion.patAct(),
    ];
    for (var i = 1; i < answers.length; i++) {
      expect(answers[i], isNot(answers[i - 1]));
    }
    expect(answers.toSet(), containsAll(patActs));
    for (var cycle = 0; cycle < 4; cycle++) {
      expect(
        answers.skip(cycle * patActs.length).take(patActs.length).toSet(),
        hasLength(patActs.length),
      );
    }
    expect(
      patActs,
      isNot(contains(anyOf(Act.enter, Act.leave, Act.eat, Act.doze))),
    );
  });

  test('shut eyes sag when sleepy and arch in a smile', () async {
    const face = FaceMap(size: Size(100, 100), eyes: [(Offset(50, 50), 10)]);

    /// Rows where the lashes are, at the middle and at the edge of the eye.
    Future<(int, int)> lashes(double joy) async {
      final recorder = ui.PictureRecorder();
      FacePainter(
        face,
        ValueNotifier(FigurePose(eyes: 0, joy: joy)),
      ).paint(Canvas(recorder), const Size(100, 100));
      final image = await recorder.endRecording().toImage(100, 100);
      final bytes = (await image.toByteData())!;
      int lowest(int x) {
        for (var y = 99; y >= 0; y--) {
          final i = (y * 100 + x) * 4;
          // The lash line is dark; the lid is skin coloured.
          if (bytes.getUint8(i + 3) > 0 && bytes.getUint8(i) < 120) return y;
        }
        return -1;
      }

      return (lowest(50), lowest(43));
    }

    final (sleepyMiddle, sleepyEdge) = await lashes(0);
    final (happyMiddle, happyEdge) = await lashes(1);
    expect(sleepyMiddle, greaterThan(sleepyEdge)); // ◡
    expect(happyMiddle, lessThan(happyEdge)); // ^
  });
}
