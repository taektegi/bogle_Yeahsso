import 'dart:ui' as ui;

import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/drawing/drawing_controller.dart';
import 'package:bogle_app/src/drawing/pencil_input.dart';
import 'package:bogle_app/src/screens/create_studio_screen.dart';
import 'package:bogle_app/src/theme/bogle_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> hardware(
  WidgetTester tester,
  String method, [
  Map<String, Object?>? args,
]) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'bogle/pencil',
    const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
    (_) {},
  );
  await tester.pump();
}

Future<void> openStudio(WidgetTester tester, {bool pencilOnly = false}) async {
  tester.view.physicalSize = const Size(1194, 834);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    PencilInput.channel,
    (_) async => {'pencilOnly': pencilOnly},
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      PencilInput.channel,
      null,
    ),
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: buildBogleTheme(),
      home: CreateStudioScreen(repository: InMemoryCharacterRepository()),
    ),
  );
  await tester.pumpAndSettle();
}

bool selected(WidgetTester tester, String name) =>
    tester
        .widget<IconButton>(
          find.byWidgetPredicate((w) => w is IconButton && w.tooltip == name),
        )
        .isSelected ==
    true;

DrawingController drawingOf(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((w) => w.painter)
    .whereType<InkPainter>()
    .single
    .controller;

void main() {
  testWidgets('double tap preserves pen settings and returns from eraser', (
    tester,
  ) async {
    await openStudio(tester);
    expect(selected(tester, '펜'), isTrue);
    await hardware(tester, 'doubleTap');
    expect(selected(tester, '지우개'), isTrue);
    await hardware(tester, 'doubleTap');
    expect(selected(tester, '펜'), isTrue);
    await tester.tap(find.byTooltip('형광펜'));
    await tester.pump();
    await hardware(tester, 'doubleTap');
    expect(selected(tester, '지우개'), isTrue);
    await hardware(tester, 'doubleTap');
    expect(selected(tester, '형광펜'), isTrue);
  });

  testWidgets('pen reselect opens settings, disabling double tap works', (
    tester,
  ) async {
    await openStudio(tester);
    expect(find.byTooltip('그리기 후 유지 설정'), findsNothing);
    await tester.tap(find.byTooltip('펜'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(SwitchListTile, '그리기 후 유지'), findsOneWidget);
    // Hardware must not change the tool underneath a modal sheet.
    await hardware(tester, 'doubleTap');
    expect(selected(tester, '펜'), isTrue);
    final toggle = find.widgetWithText(SwitchListTile, '두 번 탭으로 지우개 전환');
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pump();
    await tester.tap(find.text('완료'));
    await tester.pumpAndSettle();
    await hardware(tester, 'doubleTap');
    expect(selected(tester, '펜'), isTrue);
    await tester.tap(find.byKey(const ValueKey('studio-mode-photo')));
    await tester.pumpAndSettle();
    await hardware(tester, 'squeeze', {'action': 'tools'});
    expect(find.text('Pencil 도구'), findsNothing);
  });

  testWidgets('Pencil-only honors OS preference; fingers can still pinch', (
    tester,
  ) async {
    await openStudio(tester, pencilOnly: true);
    final canvas = find.byKey(const ValueKey('drawing-canvas'));
    final center = tester.getCenter(canvas);
    final drawing = drawingOf(tester);
    await tester.dragFrom(center, const Offset(100, 10));
    await tester.pump();
    expect(drawing.strokeCount, 0);
    final pencil = await tester.startGesture(
      center,
      kind: ui.PointerDeviceKind.stylus,
      pointer: 10,
    );
    await pencil.moveTo(center + const Offset(100, 10));
    // A palm does not cancel the Pencil line or change the canvas transform.
    final palm = await tester.startGesture(
      center + const Offset(200, 60),
      pointer: 11,
    );
    await palm.moveBy(const Offset(100, 40));
    await pencil.up();
    await palm.up();
    await tester.pump();
    expect(drawing.strokeCount, 1);
    final a = await tester.startGesture(
      center - const Offset(40, 0),
      pointer: 20,
    );
    final b = await tester.startGesture(
      center + const Offset(40, 0),
      pointer: 21,
    );
    await a.moveBy(const Offset(-70, 0));
    await b.moveBy(const Offset(70, 0));
    await a.up();
    await b.up();
    await tester.pumpAndSettle();
    expect(drawing.strokeCount, 1);
    expect(find.textContaining('%'), findsWidgets);
  });

  testWidgets(
    'squeeze opens tools once; hover never adds ink; disposed route ignores events',
    (tester) async {
      await openStudio(tester);
      final drawing = drawingOf(tester);
      final center = tester.getCenter(
        find.byKey(const ValueKey('drawing-canvas')),
      );
      await hardware(tester, 'hover', {
        'visible': true,
        'x': center.dx,
        'y': center.dy,
      });
      expect(drawing.isEmpty, isTrue);
      await hardware(tester, 'squeeze', {'action': 'tools'});
      await tester.pumpAndSettle();
      expect(find.text('Pencil 도구'), findsOneWidget);
      await hardware(tester, 'squeeze', {'action': 'tools'});
      expect(find.text('Pencil 도구'), findsOneWidget);
      await tester.tap(find.widgetWithText(SimpleDialogOption, '지우개'));
      await tester.pumpAndSettle();
      expect(selected(tester, '지우개'), isTrue);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await hardware(tester, 'doubleTap');
      expect(tester.takeException(), isNull);
    },
  );
}
