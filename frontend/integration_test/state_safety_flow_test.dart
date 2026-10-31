import 'dart:ui' as ui;

import 'package:bogle_app/main.dart' as app;
import 'package:bogle_app/src/data/character_generation.dart';
import 'package:bogle_app/src/drawing/studio_draft.dart';
import 'package:bogle_app/src/screens/loading_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('empty/erased ink, generation input and home draft restore', (
    tester,
  ) async {
    await app.main();
    await tester.pump(const Duration(seconds: 5));
    await tester.tap(find.text('친구 그리기 / 사진찍기'));
    await tester.pumpAndSettle();
    final canvas = find.byKey(const ValueKey('drawing-canvas'));
    final draft = tester
        .widget<StudioDraftScope>(find.byType(StudioDraftScope))
        .draft;
    bool enabled() => tester
        .widget<Semantics>(
          find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.label == '친구로 만들기',
          ),
        )
        .properties
        .enabled!;
    Future<void> waitForInk(bool expected) async {
      for (var i = 0; i < 80 && enabled() != expected; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(enabled(), expected);
    }

    expect(enabled(), isFalse);
    final pen = await tester.startGesture(
      tester.getCenter(canvas),
      kind: ui.PointerDeviceKind.stylus,
    );
    await pen.up();
    await tester.pump(const Duration(milliseconds: 500));
    expect(draft.drawing.strokeCount, 1);
    expect(draft.drawing.hasInk, isTrue);
    await binding.takeScreenshot('ipad-state-ink-probe');
    expect(
      await draft.drawing.exportInk(tester.getSize(canvas)),
      isNotNull,
    );
    await waitForInk(true);
    await tester.tap(find.byTooltip('친구로 만들기'));
    await tester.pump(const Duration(milliseconds: 800));
    final loading = tester.widget<LoadingScreen>(find.byType(LoadingScreen));
    expect(loading.input!.source, GenerationSource.drawing);
    expect(loading.input!.image, isNotEmpty);
    await binding.takeScreenshot('ipad-state-generation-input');
    await tester.tap(find.text('그림으로 돌아가기'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bogle-home-button')));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('친구 그리기 / 사진찍기'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));
    expect(draft.drawing.strokeCount, 1);
    expect(draft.drawing.canUndo, isTrue);
    await waitForInk(true);
    await binding.takeScreenshot('ipad-state-draft-restored');
    await tester.tap(find.byTooltip('지우개'));
    await tester.pump(const Duration(milliseconds: 200));
    final eraser = await tester.startGesture(
      tester.getCenter(canvas),
      kind: ui.PointerDeviceKind.stylus,
    );
    await eraser.up();
    await tester.pump(const Duration(milliseconds: 500));
    await waitForInk(false);
    await binding.takeScreenshot('ipad-state-erased-blocked');
    expect(tester.takeException(), isNull);
  });
}
