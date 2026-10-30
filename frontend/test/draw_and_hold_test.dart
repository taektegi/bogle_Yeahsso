import 'dart:ui' as ui;

import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/drawing/drawing_controller.dart';
import 'package:bogle_app/src/drawing/shape_recognizer.dart';
import 'package:bogle_app/src/screens/create_studio_screen.dart';
import 'package:bogle_app/src/theme/bogle_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'shape_recognizer_test.dart' show polygon;

Future<int> alphaAt(DrawingController drawing, Offset point) async {
  final recorder = ui.PictureRecorder();
  drawing.paint(Canvas(recorder), const Size(300, 300));
  final picture = recorder.endRecording();
  final image = await picture.toImage(300, 300);
  final bytes = await image.toByteData();
  final alpha = bytes!.getUint8(
    (point.dy.toInt() * 300 + point.dx.toInt()) * 4 + 3,
  );
  image.dispose();
  picture.dispose();
  return alpha;
}

void line(
  DrawingController drawing, {
  DrawingTool tool = DrawingTool.pen,
  double scale = 1,
}) {
  drawing.begin(const Offset(20, 100), Colors.red, 2, tool, inputScale: scale);
  drawing.extend(const Offset(120, 104));
  drawing.extend(const Offset(220, 100));
}

void main() {
  testWidgets('hold threshold, Pencil jitter, undo raw line and redo shape', (
    tester,
  ) async {
    final drawing = DrawingController();
    addTearDown(drawing.dispose);
    line(drawing);
    await tester.pump(const Duration(milliseconds: 600));
    expect(drawing.activeShape, isNull);
    drawing.extend(const Offset(220.5, 100.2));
    await tester.pump(const Duration(milliseconds: 60));
    expect(drawing.activeShape, SketchShape.line);
    drawing.end();
    await tester.runAsync(() async {
      expect(await alphaAt(drawing, const Offset(120, 100)), greaterThan(200));
      drawing.undo();
      expect(drawing.strokeCount, 1);
      expect(await alphaAt(drawing, const Offset(120, 100)), 0);
      drawing.redo();
      expect(await alphaAt(drawing, const Offset(120, 100)), greaterThan(200));
    });
    drawing.undo();
    drawing.undo();
    expect(drawing.isEmpty, isTrue);
  });

  testWidgets('release, cancel, disable and erasing never correct later', (
    tester,
  ) async {
    for (final mode in ['release', 'cancel', 'disable', 'eraser']) {
      final drawing = DrawingController();
      line(
        drawing,
        tool: mode == 'eraser' ? DrawingTool.eraser : DrawingTool.pen,
      );
      switch (mode) {
        case 'release':
          drawing.end();
        case 'cancel':
          drawing.cancel();
        case 'disable':
          drawing.configureShapes(enabled: false, snap: true, fill: false);
      }
      await tester.pump(const Duration(seconds: 1));
      expect(drawing.activeShape, isNull);
      drawing.dispose();
    }
    final drawing = DrawingController();
    line(drawing);
    drawing.dispose();
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('movement resumes freehand; hold tolerance follows zoom', (
    tester,
  ) async {
    final drawing = DrawingController();
    addTearDown(drawing.dispose);
    line(drawing, scale: 4);
    await tester.pump(DrawingController.holdDuration);
    expect(drawing.activeShape, SketchShape.line);
    drawing.extend(const Offset(220.5, 100));
    expect(drawing.activeShape, SketchShape.line);
    drawing.extend(const Offset(220, 120));
    expect(drawing.activeShape, isNull);
    await tester.pump(DrawingController.holdDuration);
    expect(drawing.activeShape, isNull);
    drawing.end();
  });

  testWidgets('closed shapes fill and remain compatible with stroke erasing', (
    tester,
  ) async {
    final drawing = DrawingController()..fillShapes = true;
    addTearDown(drawing.dispose);
    final points = polygon([
      const Offset(30, 30),
      const Offset(200, 30),
      const Offset(200, 180),
      const Offset(30, 180),
      const Offset(30, 30),
    ]);
    drawing.begin(points.first, Colors.blue, 3, DrawingTool.marker);
    for (final p in points.skip(1)) {
      drawing.extend(p);
    }
    await tester.pump(DrawingController.holdDuration);
    expect(drawing.activeShape, SketchShape.rectangle);
    drawing.end();
    await tester.runAsync(() async {
      expect(await alphaAt(drawing, const Offset(100, 100)), 255);
    });
    drawing.eraseStrokesAt(const Offset(100, 100), 3);
    drawing.endStrokeErase();
    expect(drawing.isEmpty, isTrue);
    drawing.undo();
    expect(drawing.strokeCount, 1);
  });

  testWidgets('nearby line endpoints snap only when enabled', (tester) async {
    for (final snap in [true, false]) {
      final drawing = DrawingController()..snapToShapes = snap;
      drawing.begin(const Offset(20, 100), Colors.red, 2, DrawingTool.pen);
      drawing.extend(const Offset(70, 100));
      drawing.extend(const Offset(120, 100));
      await tester.pump(DrawingController.holdDuration);
      drawing.end();
      drawing.begin(const Offset(127, 107), Colors.blue, 2, DrawingTool.pen);
      drawing.extend(const Offset(127, 150));
      drawing.extend(const Offset(127, 220));
      await tester.pump(DrawingController.holdDuration);
      drawing.end();
      await tester.runAsync(() async {
        expect(
          await alphaAt(drawing, const Offset(123, 150)),
          snap ? greaterThan(100) : 0,
        );
      });
      drawing.dispose();
    }
  });

  testWidgets(
    'Pencil hold survives a resting palm; pen reselect opens settings',
    (tester) async {
      tester.view.physicalSize = const Size(1194, 834);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildBogleTheme(),
          home: CreateStudioScreen(repository: InMemoryCharacterRepository()),
        ),
      );
      final canvas = find.byKey(const ValueKey('drawing-canvas'));
      final painter = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<InkPainter>()
          .single;
      final start = tester.getTopLeft(canvas) + const Offset(100, 150);
      final gesture = await tester.startGesture(
        start,
        kind: ui.PointerDeviceKind.stylus,
      );
      await gesture.moveTo(start + const Offset(100, 3));
      await gesture.moveTo(start + const Offset(200, 0));
      await tester.pump(DrawingController.holdDuration);
      expect(painter.controller.activeShape, SketchShape.line);
      final second = await tester.startGesture(
        start + const Offset(250, 100),
        pointer: 2,
      );
      await tester.pump(const Duration(seconds: 1));
      expect(painter.controller.activeShape, SketchShape.line);
      expect(painter.controller.strokeCount, 0);
      await second.up();
      await gesture.up();
      final before = tester.getRect(canvas);
      await tester.tap(find.byTooltip('펜'));
      await tester.pumpAndSettle();
      expect(find.text('다른 모양에 스냅'), findsOneWidget);
      expect(find.text('색상 채우기'), findsOneWidget);
      await tester.tap(find.widgetWithText(SwitchListTile, '그리기 후 유지'));
      await tester.pumpAndSettle();
      expect(painter.controller.drawAndHold, isFalse);
      await tester.tap(find.text('완료'));
      await tester.pumpAndSettle();
      expect(tester.getRect(canvas), before);
      expect(tester.takeException(), isNull);
    },
  );
}
