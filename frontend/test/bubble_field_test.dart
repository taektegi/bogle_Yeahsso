import 'package:bogle_app/src/widgets/bubble_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void expectOriginalsSeparated(WidgetTester tester) {
  final circles = <({int id, Offset center, double radius})>[];
  for (var i = 0; i < 8; i++) {
    final original = find.byKey(ValueKey('bubble-$i'));
    if (original.evaluate().isEmpty) continue;
    // Measure inside Transform to include the animated jelly distortion.
    final rect = tester.getRect(
      find.descendant(of: original, matching: find.byType(GestureDetector)),
    );
    circles.add((id: i, center: rect.center, radius: rect.longestSide / 2));
  }
  for (var i = 0; i < circles.length; i++) {
    for (var j = i + 1; j < circles.length; j++) {
      final a = circles[i], b = circles[j];
      expect(
        (a.center - b.center).distance - a.radius - b.radius,
        greaterThanOrEqualTo(12),
        reason: 'Original bubbles ${a.id} and ${b.id} need a visible gap',
      );
    }
  }
}

void main() {
  testWidgets(
    'new Figma composition contains eight round, generation-only bubbles',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final size in [const Size(1194, 834), const Size(1366, 1024)]) {
        tester.view.physicalSize = size;
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: BubbleField(running: true, still: true)),
          ),
        );
        expect(generationBubbleAssets.length, 8);
        for (var i = 0; i < 8; i++) {
          final rect = tester.getRect(find.byKey(ValueKey('bubble-$i')));
          expect(rect.width, closeTo(rect.height, .001));
          expect(
            find.image(AssetImage(generationBubbleAssets[i])),
            findsOneWidget,
          );
        }
        final beige = tester.getCenter(find.byKey(const ValueKey('bubble-1')));
        expect(beige.dx / size.width, closeTo(478.212 / 1194, .00001));
        expect(beige.dy / size.height, closeTo(797.756 / 834, .00001));
        final lime = tester.getCenter(find.byKey(const ValueKey('bubble-5')));
        expect(lime.dx / size.width, closeTo(725 / 1194, .00001));
        expect(lime.dy / size.height, closeTo(175.202 / 834, .00001));
        expectOriginalsSeparated(tester);
        expect(tester.binding.transientCallbackCount, 0);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('eight bubbles reach the composition and pause without jumping', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1194, 834);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Widget scene(bool running) => MaterialApp(
      home: Scaffold(body: BubbleField(running: running, still: false)),
    );
    await tester.pumpWidget(scene(true));
    await tester.pump(const Duration(milliseconds: 3600));
    for (var i = 0; i < 8; i++) {
      expect(find.byKey(ValueKey('bubble-$i')), findsOneWidget);
    }
    final center = tester.getCenter(find.byKey(const ValueKey('bubble-3')));
    expect(center.dx, closeTo(339.767, .001));
    expect(center.dy, closeTo(481.032, .001));
    await tester.pumpWidget(scene(false));
    await tester.pump(const Duration(seconds: 30));
    expect(tester.getCenter(find.byKey(const ValueKey('bubble-3'))), center);
    await tester.pumpWidget(scene(true));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      tester.getCenter(find.byKey(const ValueKey('bubble-3'))).dy,
      lessThan(center.dy),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('originals never overlap at entry, wrap or after a split', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final size in [const Size(1194, 834), const Size(1366, 1024)]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: BubbleField(running: true, still: false)),
        ),
      );
      // Check frame zero, the initial entrances, and many full wrap cycles.
      expectOriginalsSeparated(tester);
      for (var sample = 0; sample < 1200; sample++) {
        await tester.pump(const Duration(milliseconds: 100));
        expectOriginalsSeparated(tester);
        if (sample == 359) {
          await tester.tap(
            find.byKey(const ValueKey('bubble-3')),
            warnIfMissed: false,
          );
          await tester.pump();
          expect(find.byKey(const ValueKey('bubble-3')), findsNothing);
          expect(
            find.image(AssetImage(generationBubbleAssets[3])),
            findsNWidgets(2),
          );
        }
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
  });
}
