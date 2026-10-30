import 'dart:math' as math;

import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/drawing/drawing_controller.dart';
import 'package:bogle_app/src/drawing/shape_recognizer.dart';
import 'package:bogle_app/src/drawing/pencil_input.dart';
import 'package:bogle_app/src/screens/create_studio_screen.dart';
import 'package:bogle_app/src/theme/bogle_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('draw and hold on an iPad canvas', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildBogleTheme(),
        home: CreateStudioScreen(repository: InMemoryCharacterRepository()),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      await PencilInput.attach(),
      isA<bool>(),
      reason: 'UIKit Pencil bridge must register on iOS',
    );
    final canvas = tester.getRect(find.byKey(const ValueKey('drawing-canvas')));
    final drawing = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((w) => w.painter)
        .whereType<InkPainter>()
        .single
        .controller;

    Future<void> draw(List<Offset> points, SketchShape expected) async {
      final gesture = await tester.startGesture(canvas.topLeft + points.first);
      for (final point in points.skip(1)) {
        await gesture.moveTo(canvas.topLeft + point);
        await tester.pump(const Duration(milliseconds: 12));
      }
      await tester.pump(const Duration(milliseconds: 750));
      expect(drawing.activeShape, expected);
      await gesture.up();
      await tester.pumpAndSettle();
    }

    List<Offset> polygon(List<Offset> corners) => [
      for (var i = 0; i < corners.length - 1; i++)
        for (var j = 0; j < 14; j++)
          Offset.lerp(corners[i], corners[i + 1], j / 14)! +
              Offset(math.sin(j * 2) * 1.8, math.cos(j * 2) * 1.8),
      corners.last,
    ];
    await draw(
      polygon([const Offset(90, 160), const Offset(380, 170)]),
      SketchShape.line,
    );
    await draw(
      List.generate(85, (i) {
        final t = i / 84 * 2 * math.pi;
        return Offset(235 + 105 * math.cos(t), 365 + 105 * math.sin(t));
      }),
      SketchShape.ellipse,
    );
    await draw(
      polygon([
        const Offset(460, 255),
        const Offset(715, 255),
        const Offset(715, 465),
        const Offset(460, 465),
        const Offset(460, 255),
      ]),
      SketchShape.rectangle,
    );
    await draw(
      polygon([
        const Offset(800, 465),
        const Offset(925, 250),
        const Offset(1050, 465),
        const Offset(800, 465),
      ]),
      SketchShape.triangle,
    );
    await binding.takeScreenshot('ipad-studio-held-shapes');
    await tester.tap(find.byTooltip('펜'));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('ipad-studio-shape-settings');
    await tester.tap(find.text('완료'));
    await tester.pumpAndSettle();
    expect(drawing.strokeCount, 4);
    expect(tester.takeException(), isNull);
  });
}
