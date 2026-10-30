import 'dart:ui' as ui;

import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/drawing/drawing_controller.dart';
import 'package:bogle_app/src/screens/create_studio_screen.dart';
import 'package:bogle_app/src/theme/bogle_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('eraser removes ink and undo/redo restores exact history', () async {
    final drawing = DrawingController();
    addTearDown(drawing.dispose);
    drawing.begin(const Offset(10, 50), Colors.red, 20, DrawingTool.pen);
    drawing.extend(const Offset(90, 50));
    drawing.end();
    drawing.begin(const Offset(50, 10), Colors.black, 20, DrawingTool.eraser);
    drawing.extend(const Offset(50, 90));
    drawing.end();

    Future<int> alphaAtCenter() async {
      final recorder = ui.PictureRecorder();
      drawing.paint(Canvas(recorder), const Size(100, 100));
      final picture = recorder.endRecording();
      final image = await picture.toImage(100, 100);
      final bytes = await image.toByteData();
      final alpha = bytes!.getUint8((50 * 100 + 50) * 4 + 3);
      image.dispose();
      picture.dispose();
      return alpha;
    }

    expect(await alphaAtCenter(), 0);
    drawing.undo();
    expect(await alphaAtCenter(), 255);
    drawing.redo();
    expect(await alphaAtCenter(), 0);
    drawing.clear();
    expect(drawing.isEmpty, isTrue);
    drawing.undo();
    expect(drawing.strokeCount, 2);
    drawing.undo();
    drawing.begin(const Offset(20, 20), Colors.blue, 8, DrawingTool.pen);
    drawing.end();
    expect(drawing.canRedo, isFalse);
  });

  for (final size in [const Size(1024, 768), const Size(1210, 834)]) {
    testWidgets('large canvas and tools remain usable at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildBogleTheme(),
          home: CreateStudioScreen(repository: InMemoryCharacterRepository()),
        ),
      );
      final canvas = find.byKey(const ValueKey('drawing-canvas'));
      final before = tester.getRect(canvas);
      expect(before.width, greaterThan(size.width * 0.95));
      expect(before.height, greaterThan(size.height * 0.85));
      // The tools stand in one column down the right of the page, under
      // the ✓ that makes the friend.
      final done = tester.getRect(find.byTooltip('친구로 만들기'));
      final pen = tester.getRect(find.byTooltip('펜'));
      final undoAt = tester.getRect(find.byTooltip('되돌리기'));
      // Set well apart, with its own caption, so it isn't read as a tool.
      expect(pen.top - done.bottom, greaterThanOrEqualTo(28));
      expect(find.text('완성'), findsOneWidget);
      expect(pen.bottom, lessThanOrEqualTo(undoAt.top));
      expect(pen.center.dx, closeTo(done.center.dx, 1));
      expect(undoAt.center.dx, lessThan(before.center.dx));
      expect(pen.width, greaterThanOrEqualTo(44));
      expect(before.right - done.right, lessThan(40));
      expect(done.bottom, lessThan(before.bottom));
      await tester.dragFrom(before.center, const Offset(100, 30));
      await tester.pump();
      final undo = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.undo_rounded),
      );
      expect(undo.onPressed, isNotNull);
      await tester.tap(find.byTooltip('지우개'));
      await tester.dragFrom(before.center, const Offset(50, 0));
      await tester.pump();
      await tester.tap(find.byTooltip('되돌리기'));
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.redo_rounded),
            )
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byTooltip('도구 숨기기'));
      await tester.pumpAndSettle();
      expect(tester.getRect(canvas), before);
      expect(find.byTooltip('되돌리기').hitTestable(), findsOneWidget);
      // Only the dock itself brings the tools back.
      await tester.tap(find.byTooltip('도구 보이기'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('되돌리기'), findsOneWidget);
      // Tapping the chosen size again fine-tunes it, as in Goodnotes.
      await tester.tap(find.byTooltip('보통 지우개'));
      await tester.pumpAndSettle();
      expect(find.text('굵기'), findsWidgets);
      await tester.tap(find.text('완료'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('펜'));
      await tester.pump();
      // The full colour panel opens directly from the colour button.
      await tester.ensureVisible(find.byTooltip('색상'));
      await tester.tap(find.byTooltip('색상'));
      await tester.pumpAndSettle();
      expect(find.text('격자'), findsOneWidget);
      expect(find.text('스펙트럼'), findsOneWidget);
      expect(find.text('불투명도'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final reducedMotion in [false, true]) {
    testWidgets(
      'toolbar geometry stays stable (reduced motion: $reducedMotion)',
      (tester) async {
        tester.view.physicalSize = const Size(1210, 834);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildBogleTheme(),
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reducedMotion),
              child: CreateStudioScreen(
                repository: InMemoryCharacterRepository(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final done = tester.getRect(find.byTooltip('친구로 만들기'));
        final pen = tester.getRect(find.byTooltip('펜'));
        final canvas = tester.getRect(
          find.byKey(const ValueKey('drawing-canvas')),
        );
        for (final label in ['지우개', '펜', '형광펜', '도구 숨기기', '도구 보이기']) {
          await tester.tap(find.byTooltip(label).hitTestable());
          await tester.pump();
          // Check intermediate frames as well as the final layout. A fitted
          // toolbar must not rescale or reposition the separate completion CTA.
          for (var frame = 0; frame < 30; frame++) {
            await tester.pump(const Duration(milliseconds: 8));
            expect(tester.getRect(find.byTooltip('친구로 만들기')), done);
            expect(
              tester.getRect(find.byKey(const ValueKey('drawing-canvas'))),
              canvas,
            );
            if (label != '도구 숨기기' && label != '도구 보이기') {
              expect(tester.getRect(find.byTooltip('펜')), pen);
            }
          }
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(tester.binding.transientCallbackCount, 0);
      },
    );
  }

  for (final reducedMotion in [false, true]) {
    testWidgets('width ripple is local and stable (reduced: $reducedMotion)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1366, 1024);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildBogleTheme(),
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reducedMotion),
            child: CreateStudioScreen(
              repository: InMemoryCharacterRepository(),
            ),
          ),
        ),
      );
      final thin = find.byTooltip('가는 펜');
      final ink = find.descendant(of: thin, matching: find.byType(InkWell));
      expect(
        tester.widget<InkWell>(ink).splashFactory,
        reducedMotion ? NoSplash.splashFactory : InkRipple.splashFactory,
      );
      expect(tester.widget<InkWell>(ink).highlightColor, Colors.transparent);
      final localMaterial = find.descendant(
        of: thin,
        matching: find.byType(Material),
      );
      expect(localMaterial, findsOneWidget);
      final before = tester.getRect(thin);
      final done = tester.getRect(find.byTooltip('친구로 만들기'));
      // Repeated selection while prior ripples are still fading must retain
      // bounds, callbacks and the selected-size detail action.
      for (final label in ['가는 펜', '굵은 펜', '보통 펜', '가는 펜']) {
        await tester.tap(find.byTooltip(label));
        await tester.pump();
        for (var frame = 0; frame < 8; frame++) {
          await tester.pump(const Duration(milliseconds: 8));
          expect(tester.getRect(thin), before);
          expect(tester.getRect(find.byTooltip('친구로 만들기')), done);
        }
      }
      await tester.pumpAndSettle();
      expect(
        tester.widget<Material>(localMaterial).color,
        BogleColors.blueSoft,
      );
      await tester.tap(thin);
      await tester.pumpAndSettle();
      expect(find.text('완료'), findsOneWidget);
      await tester.tap(find.text('완료'));
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    });
  }

  test('the stroke eraser lifts whole lines, as one undo step', () {
    final drawing = DrawingController();
    addTearDown(drawing.dispose);
    for (final y in [20.0, 60.0]) {
      drawing.begin(Offset(10, y), Colors.red, 4, DrawingTool.pen);
      drawing.extend(Offset(90, y));
      drawing.end();
    }
    drawing.eraseStrokesAt(const Offset(50, 23), 6);
    drawing.eraseStrokesAt(const Offset(50, 40), 6);
    drawing.endStrokeErase();
    expect(drawing.strokeCount, 1);
    drawing.undo();
    expect(drawing.strokeCount, 2);
  });

  testWidgets('two fingers zoom without drawing; paper patterns show', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildBogleTheme(),
        home: CreateStudioScreen(repository: InMemoryCharacterRepository()),
      ),
    );
    final canvas = find.byKey(const ValueKey('drawing-canvas'));
    final c = tester.getCenter(canvas);
    final a = await tester.startGesture(c - const Offset(40, 0), pointer: 1);
    final b = await tester.startGesture(c + const Offset(40, 0), pointer: 2);
    for (var i = 1; i <= 5; i++) {
      await a.moveTo(c - Offset(40.0 + i * 16, 0));
      await b.moveTo(c + Offset(40.0 + i * 16, 0));
      await tester.pump();
    }
    await a.up();
    await b.up();
    await tester.pumpAndSettle();
    expect(find.text('300%'), findsOneWidget);
    final undo = find.widgetWithIcon(IconButton, Icons.undo_rounded);
    expect(tester.widget<IconButton>(undo).onPressed, isNull);

    await tester.tap(find.text('원래 크기로'));
    await tester.pumpAndSettle();
    expect(find.text('300%'), findsNothing);

    await tester.ensureVisible(find.byTooltip('종이 고르기'));
    await tester.tap(find.byTooltip('종이 고르기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('모눈 종이'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('paper-grid')), findsOneWidget);
  });
}
