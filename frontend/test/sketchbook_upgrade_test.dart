import 'package:bogle_app/src/data/local_store.dart';
import 'package:bogle_app/src/drawing/drawing_controller.dart';
import 'package:bogle_app/src/drawing/studio_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'pencil_input_test.dart' as pencil;

void main() {
  final canvas = find.byKey(const ValueKey('drawing-canvas'));
  List<double> view(WidgetTester tester) => tester
      .widget<Transform>(
        find.descendant(of: canvas, matching: find.byType(Transform)).first,
      )
      .transform
      .storage
      .toList();
  Future<void> zoom(WidgetTester tester) async {
    final c = tester.getCenter(canvas);
    final a = await tester.startGesture(c - const Offset(40, 0), pointer: 20);
    final b = await tester.startGesture(c + const Offset(40, 0), pointer: 21);
    await a.moveBy(const Offset(-60, 0));
    await b.moveBy(const Offset(60, 0));
    await a.up();
    await b.up();
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Pencil-only one finger pans, and a pinch continues with one finger',
    (tester) async {
      await pencil.openStudio(tester, pencilOnly: true);
      await zoom(tester);
      final before = view(tester);
      await tester.dragFrom(tester.getCenter(canvas), const Offset(80, 20));
      await tester.pump();
      expect(view(tester)[12], closeTo(before[12] + 80, .001));
      expect(pencil.drawingOf(tester).strokeCount, 0);
      final c = tester.getCenter(canvas);
      final a = await tester.startGesture(c - const Offset(40, 0), pointer: 30);
      final b = await tester.startGesture(c + const Offset(40, 0), pointer: 31);
      await b.up();
      await tester.pump();
      final x = view(tester)[12];
      await a.moveBy(const Offset(-50, 0));
      await tester.pump();
      expect(view(tester)[12], closeTo(x - 50, .001));
      await a.up();
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'hand tool pans without ink and selecting the pen resumes finger drawing',
    (tester) async {
      await pencil.openStudio(tester);
      await zoom(tester);
      await tester.tap(find.byTooltip('화면 이동'));
      await tester.pump();
      final before = view(tester);
      await tester.dragFrom(tester.getCenter(canvas), const Offset(70, 0));
      await tester.pump();
      expect(view(tester)[12], greaterThan(before[12]));
      expect(pencil.drawingOf(tester).strokeCount, 0);
      await tester.tap(find.byTooltip('펜'));
      await tester.pump();
      await tester.dragFrom(tester.getCenter(canvas), const Offset(80, 20));
      expect(pencil.drawingOf(tester).strokeCount, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('pinch rolls back whole-stroke erasure', (tester) async {
    await pencil.openStudio(tester);
    final c = tester.getCenter(canvas);
    await tester.dragFrom(c, const Offset(100, 0));
    await tester.pump();
    await tester.tap(find.byTooltip('지우개'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('선 지우기'));
    await tester.tap(find.byTooltip('선 지우기'));
    await tester.pump();
    final a = await tester.startGesture(c + const Offset(20, 0), pointer: 40);
    final b = await tester.startGesture(c + const Offset(140, 0), pointer: 41);
    await a.moveBy(const Offset(-20, 0));
    await b.moveBy(const Offset(20, 0));
    await a.up();
    await b.up();
    await tester.pump();
    expect(pencil.drawingOf(tester).strokeCount, 1);
    pencil.drawingOf(tester).undo();
    expect(pencil.drawingOf(tester).strokeCount, 0);
    await tester.pumpWidget(const SizedBox());
  });

  test(
    'draft survives a new app owner with exact ink, undo, zoom and preferences',
    () async {
      final store = MemoryStore();
      final original = StudioDraft(store: store);
      await original.ready;
      original.drawing.begin(
        const Offset(10, 20),
        Colors.red,
        6,
        DrawingTool.pen,
      );
      for (var i = 1; i < 40; i++) {
        original.drawing.extend(Offset(10 + i * 3.0, 20 + i % 4));
      }
      original.drawing.end();
      original
        ..scale = 2.5
        ..pan = const Offset(-120, -80)
        ..pencilOnly = true
        ..leftHanded = true;
      original.widths[DrawingTool.pen] = [2, 7, 20];
      final ink = await original.drawing.exportInk(const Size(300, 200));
      await original.flush();
      original.dispose();
      final restored = StudioDraft(store: store);
      await restored.ready;
      expect(await restored.drawing.exportInk(const Size(300, 200)), ink);
      expect(restored.scale, 2.5);
      expect(restored.pan, const Offset(-120, -80));
      expect(restored.pencilOnly, isTrue);
      expect(restored.leftHanded, isTrue);
      expect(restored.widths[DrawingTool.pen], [2, 7, 20]);
      restored.drawing.undo();
      expect(restored.drawing.isEmpty, isTrue);
      restored.drawing.redo();
      expect(restored.drawing.strokeCount, 1);
      await restored.flush();
      restored.dispose();
    },
  );
}
