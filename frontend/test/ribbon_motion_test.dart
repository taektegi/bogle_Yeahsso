import 'package:bogle_app/src/widgets/ribbon_motion.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const motion = RibbonMotion(
    origin: Offset(140, 540),
    apex: Offset(600, 90),
    flight: 1.5,
    fall: 6.3,
    endY: 800,
    length: 150,
    sway: 10,
    phase: 1,
  );

  test('flight turns continuously without stopping sideways at the apex', () {
    const dt = .001;
    final before = (motion.head(1.5) - motion.head(1.5 - dt)) / dt;
    final after = (motion.head(1.5 + dt) - motion.head(1.5)) / dt;
    expect(before.dx, greaterThan(30));
    expect((before - after).distance, lessThan(1));
    expect(motion.head(0), motion.origin);
    expect(motion.head(1.5), motion.apex);
    expect(motion.head(8).dy, greaterThan(800));
  });

  test('paper keeps its length through ascent, apex and descent', () {
    for (final t in [.4, .9, 1.5, 1.7, 2.0, 3.0, 6.0, 9.0]) {
      final points = motion.trail(t);
      var length = 0.0;
      for (var i = 1; i < points.length; i++) {
        length += (points[i] - points[i - 1]).distance;
      }
      expect(length, closeTo(150, 4), reason: 'at $t seconds');
      expect(points.length, 25);
      expect(points.every((p) => p.dx.isFinite && p.dy.isFinite), isTrue);
    }
    expect(motion.trail(10).every((p) => p.dy > 600), isTrue);
  });

  test(
    'ribbon positions do not jump around the apex or depend on frame rate',
    () {
      final first = motion.trail(1.5);
      motion.trail(2); // Out-of-order sampling cannot mutate simulation state.
      expect(motion.trail(1.5), first);
      for (var t = 1.3; t < 2.5; t += 1 / 60) {
        final a = motion.trail(t), b = motion.trail(t + 1 / 120);
        for (var i = 0; i < a.length; i++) {
          expect((b[i] - a[i]).distance, lessThan(8));
        }
      }
    },
  );

  test('a ribbon sent through the character turns there, out of sight', () {
    // Left cannon, crossing behind a character at (500, 300) to the right.
    const through = RibbonMotion(
      origin: Offset(140, 900),
      via: Offset(500, 300),
      bend: Offset(100, 340),
      apex: Offset(900, 150),
      flight: 1.5,
      fall: 6.3,
      endY: 1100,
      length: 150,
      sway: 10,
      phase: 1,
    );
    const toVia = 1.5 * .32;
    expect(through.head(0), through.origin);
    expect((through.head(toVia) - through.via!).distance, lessThan(.01));
    expect((through.head(1.5) - through.apex).distance, lessThan(.01));

    // On the way in it rises along its own side, never cutting across the
    // middle of the page below the character.
    for (var t = 0.0; t < toVia * .7; t += .01) {
      expect(through.head(t).dx, lessThan(380));
    }

    // It rounds over the top instead of stopping dead and hooking back.
    const dt = .001;
    final before = (through.head(1.5) - through.head(1.5 - dt)) / dt;
    final after = (through.head(1.5 + dt) - through.head(1.5)) / dt;
    expect(before.dx, greaterThan(10));
    expect((before - after).distance, lessThan(1));
    expect(through.head(9).dy, greaterThan(1100));
  });
}
