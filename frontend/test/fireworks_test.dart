import 'dart:ui' as ui;

import 'package:bogle_app/src/widgets/fireworks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ribbons rise behind content and fall in front on one clock', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Fireworks(
          style: FireworksStyle.screenFan,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => taps++,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    Future<int> upperInk(String key) async {
      final paint = tester.widget<CustomPaint>(
        find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(CustomPaint),
        ),
      );
      final recorder = ui.PictureRecorder();
      paint.painter!.paint(Canvas(recorder), const Size(800, 600));
      final picture = recorder.endRecording();
      final result = await tester.runAsync(() async {
        final image = await picture.toImage(800, 600);
        final bytes = (await image.toByteData())!;
        var pixels = 0;
        // Ignore the cones, which intentionally stay in the foreground.
        for (var i = 3; i < 800 * 450 * 4; i += 4) {
          if (bytes.getUint8(i) > 20) pixels++;
        }
        image.dispose();
        return pixels;
      });
      picture.dispose();
      return result!;
    }

    await tester.pump(const Duration(milliseconds: 1400));
    expect(await upperInk('fireworks-behind-canvas'), greaterThan(500));
    expect(await upperInk('fireworks-canvas'), 0);
    expect(tester.binding.transientCallbackCount, 1);
    await tester.pump(const Duration(milliseconds: 1000));
    expect(await upperInk('fireworks-behind-canvas'), greaterThan(100));
    expect(await upperInk('fireworks-canvas'), greaterThan(100));
    await tester.pump(const Duration(milliseconds: 900));
    expect(await upperInk('fireworks-behind-canvas'), 0);
    expect(await upperInk('fireworks-canvas'), greaterThan(500));
    await tester.tapAt(const Offset(400, 300));
    expect(taps, 1);
    await tester.pumpWidget(const SizedBox());
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets(
    'inactive celebration preserves content when starting and reducing motion',
    (tester) async {
      Widget page({bool active = false, bool reduced = false}) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: Fireworks(
            active: active,
            style: FireworksStyle.screenFan,
            child: const Material(child: TextField()),
          ),
        ),
      );
      await tester.pumpWidget(page());
      await tester.enterText(find.byType(TextField), 'kept');
      final element = tester.element(find.byType(TextField));
      expect(find.byKey(const ValueKey('fireworks-canvas')), findsNothing);
      await tester.pumpWidget(page(active: true));
      expect(tester.element(find.byType(TextField)), same(element));
      expect(find.text('kept'), findsOneWidget);
      await tester.pumpWidget(page(active: true, reduced: true));
      expect(tester.element(find.byType(TextField)), same(element));
      expect(find.byKey(const ValueKey('fireworks-canvas')), findsNothing);
      expect(
        find.byKey(const ValueKey('fireworks-behind-canvas')),
        findsNothing,
      );
    },
  );

  Widget scene({
    bool reduced = false,
    VoidCallback? onTap,
    FireworksStyle style = FireworksStyle.handHeld,
  }) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduced),
      child: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap),
          Fireworks(style: style),
        ],
      ),
    ),
  );

  testWidgets('celebration paints, allows taps and stops after one show', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(scene(onTap: () => taps++));
    expect(find.byKey(const ValueKey('fireworks-canvas')), findsOneWidget);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
    }
    await tester.tapAt(const Offset(100, 100));
    expect(taps, 1);
    // The single opening is over; its long streamers continue falling.
    await tester.pump(const Duration(milliseconds: 4000));
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pump(Fireworks.duration - const Duration(milliseconds: 7900));
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(scene());
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('streamers drift down and the completed canvas becomes empty', (
    tester,
  ) async {
    await tester.pumpWidget(scene());
    Future<({int pixels, double y, int bottomPixels})> ink() async {
      final paint = tester.widget<CustomPaint>(
        find.descendant(
          of: find.byKey(const ValueKey('fireworks-canvas')),
          matching: find.byType(CustomPaint),
        ),
      );
      final recorder = ui.PictureRecorder();
      paint.painter!.paint(Canvas(recorder), const Size(800, 600));
      final picture = recorder.endRecording();
      final result = await tester.runAsync(() async {
        final image = await picture.toImage(800, 600);
        final data = (await image.toByteData())!;
        var pixels = 0;
        var y = 0.0;
        var bottomPixels = 0;
        for (var i = 3; i < data.lengthInBytes; i += 4) {
          if (data.getUint8(i) > 20) {
            pixels++;
            y += (i ~/ 4) ~/ 800;
            if ((i ~/ 4) ~/ 800 >= 570) bottomPixels++;
          }
        }
        image.dispose();
        return (
          pixels: pixels,
          y: pixels == 0 ? 0.0 : y / pixels,
          bottomPixels: bottomPixels,
        );
      });
      picture.dispose();
      return result!;
    }

    expect((await ink()).pixels, 0);
    await tester.pump(const Duration(milliseconds: 500));
    expect((await ink()).pixels, greaterThan(500));
    await tester.pump(const Duration(milliseconds: 2500));
    final high = await ink();
    await tester.pump(const Duration(milliseconds: 3000));
    final low = await ink();
    expect(high.pixels, greaterThan(500));
    expect(low.pixels, greaterThan(500));
    expect(low.y, greaterThan(high.y + 150));
    await tester.pump(const Duration(milliseconds: 2000));
    expect((await ink()).bottomPixels, greaterThan(40));
    await tester.pump(const Duration(seconds: 4));
    expect((await ink()).pixels, 0);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('background pauses playback and disposal cancels the ticker', (
    tester,
  ) async {
    await tester.pumpWidget(scene());
    await tester.pump(const Duration(seconds: 2));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 12));
    expect(tester.binding.transientCallbackCount, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cones move out beside the controls they must keep clear', (
    tester,
  ) async {
    final buttons = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Fireworks(
          style: FireworksStyle.screenFan,
          keepClear: buttons,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(key: buttons, width: 560, height: 88),
          ),
        ),
      ),
    );
    // Just the two cones, before they pop.
    await tester.pump(const Duration(milliseconds: 650));
    final paint = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byKey(const ValueKey('fireworks-canvas')),
        matching: find.byType(CustomPaint),
      ),
    );
    final recorder = ui.PictureRecorder();
    paint.painter!.paint(Canvas(recorder), const Size(800, 600));
    final picture = recorder.endRecording();
    final ink = await tester.runAsync(() async {
      final image = await picture.toImage(800, 600);
      final bytes = (await image.toByteData())!;
      var left = 0, over = 0, right = 0;
      for (var i = 3; i < bytes.lengthInBytes; i += 4) {
        if (bytes.getUint8(i) < 20) continue;
        final x = (i ~/ 4) % 800;
        if (x < 120) {
          left++;
        } else if (x > 680) {
          right++;
        } else {
          over++;
        }
      }
      image.dispose();
      return (left: left, over: over, right: right);
    });
    picture.dispose();
    expect(ink!.left, greaterThan(300));
    expect(ink.right, greaterThan(300));
    // The usual spot (x ≈ 128) would sit on the buttons (120–680).
    expect(ink.over, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'two compact cones leave centre clear, launch upward and ribbons exit below',
    (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        scene(style: FireworksStyle.screenFan, onTap: () => taps++),
      );
      Future<({Rect bounds, int left, int right, int middle, int bottom})>
      ink() async {
        final paint = tester.widget<CustomPaint>(
          find.descendant(
            of: find.byKey(const ValueKey('fireworks-canvas')),
            matching: find.byType(CustomPaint),
          ),
        );
        final recorder = ui.PictureRecorder();
        paint.painter!.paint(Canvas(recorder), const Size(800, 600));
        final picture = recorder.endRecording();
        final result = await tester.runAsync(() async {
          final image = await picture.toImage(800, 600);
          final bytes = (await image.toByteData())!;
          var minX = 800.0, maxX = 0.0, minY = 600.0, maxY = 0.0;
          var left = 0, right = 0, middle = 0, bottom = 0;
          for (var i = 3; i < bytes.lengthInBytes; i += 4) {
            if (bytes.getUint8(i) < 40) continue;
            final x = ((i ~/ 4) % 800).toDouble(),
                y = ((i ~/ 4) ~/ 800).toDouble();
            if (x < minX) minX = x;
            if (x > maxX) maxX = x;
            if (y < minY) minY = y;
            if (y > maxY) maxY = y;
            if (x < 300) left++;
            if (x > 500) right++;
            if (x > 350 && x < 450) middle++;
            if (y >= 570) bottom++;
          }
          image.dispose();
          return (
            bounds: Rect.fromLTRB(minX, minY, maxX, maxY),
            left: left,
            right: right,
            middle: middle,
            bottom: bottom,
          );
        });
        picture.dispose();
        return result!;
      }

      await tester.pump(const Duration(milliseconds: 650));
      final cone = await ink();
      expect(cone.bounds.center.dx, closeTo(400, 4));
      expect(cone.bounds.top, greaterThan(500));
      expect(cone.bounds.width, greaterThan(500));
      expect(cone.bounds.height, lessThan(90));
      expect(cone.left, greaterThan(500));
      expect(cone.right, greaterThan(500));
      expect(cone.middle, 0);
      expect(cone.bounds.bottom, lessThan(600));
      await tester.tapAt(const Offset(150, 550));
      expect(taps, 1); // The foreground cones never swallow button taps.
      await tester.pump(const Duration(milliseconds: 1200));
      final rising = await ink();
      expect(rising.bounds.top, lessThan(200));
      expect(rising.left + rising.right, greaterThan(500));
      await tester.pump(const Duration(milliseconds: 2150));
      final wings = await ink();
      expect(wings.left, greaterThan(500));
      expect(wings.right, greaterThan(500));
      expect(wings.left / wings.right, inInclusiveRange(.5, 2));
      expect(wings.middle, lessThan(50));
      expect(wings.bounds.width, greaterThan(600));
      await tester.pump(const Duration(seconds: 4));
      expect((await ink()).bottom, greaterThan(30));
      await tester.pump(const Duration(seconds: 4));
      final end = await ink();
      expect(end.left + end.right + end.middle + end.bottom, 0);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('screen fan respects reduced motion without blocking controls', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      scene(
        style: FireworksStyle.screenFan,
        reduced: true,
        onTap: () => taps++,
      ),
    );
    await tester.tapAt(const Offset(400, 500));
    expect(taps, 1);
    expect(find.byKey(const ValueKey('fireworks-canvas')), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('held cone follows the artwork hand when its layout moves', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final hand = GlobalKey();
    var position = const Offset(100, 200);
    late StateSetter move;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            move = setState;
            return Stack(
              fit: StackFit.expand,
              children: [
                Fireworks(handTarget: hand, handFraction: const Offset(.8, .3)),
                Positioned(
                  left: position.dx,
                  top: position.dy,
                  child: SizedBox(key: hand, width: 280, height: 170),
                ),
              ],
            );
          },
        ),
      ),
    );
    Future<Rect> inkBounds() async {
      final paint = tester.widget<CustomPaint>(
        find.descendant(
          of: find.byKey(const ValueKey('fireworks-canvas')),
          matching: find.byType(CustomPaint),
        ),
      );
      final recorder = ui.PictureRecorder();
      paint.painter!.paint(Canvas(recorder), const Size(800, 600));
      final picture = recorder.endRecording();
      final result = await tester.runAsync(() async {
        final image = await picture.toImage(800, 600);
        final bytes = (await image.toByteData())!;
        var left = 800.0, right = 0.0, top = 600.0, bottom = 0.0;
        for (var i = 3; i < bytes.lengthInBytes; i += 4) {
          if (bytes.getUint8(i) < 40) continue;
          final x = ((i ~/ 4) % 800).toDouble(),
              y = ((i ~/ 4) ~/ 800).toDouble();
          if (x < left) left = x;
          if (x > right) right = x;
          if (y < top) top = y;
          if (y > bottom) bottom = y;
        }
        image.dispose();
        return Rect.fromLTRB(left, top, right, bottom);
      });
      picture.dispose();
      return result!;
    }

    await tester.pump(const Duration(milliseconds: 650));
    final before = await inkBounds();
    final grip = position + const Offset(280 * .8, 170 * .3);
    expect(before.inflate(5).contains(grip), isTrue);
    move(() => position += const Offset(180, 100));
    await tester.pump(const Duration(milliseconds: 1));
    final after = await inkBounds();
    expect(after.left - before.left, closeTo(180, 1));
    expect(after.top - before.top, closeTo(100, 1));
    expect(after.size, before.size);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion suppresses the show and stops an active ticker', (
    tester,
  ) async {
    await tester.pumpWidget(scene(reduced: true));
    expect(find.byKey(const ValueKey('fireworks-canvas')), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(scene());
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpWidget(scene(reduced: true));
    expect(find.byKey(const ValueKey('fireworks-canvas')), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });
}
