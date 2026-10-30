import 'dart:ui';

import 'package:bogle_app/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Home floats on a loop, so pumpAndSettle never settles there; draw real
/// frames for a while instead (a single live pump draws only one frame).
Future<void> pumpFrames(WidgetTester tester, Duration total) async {
  const step = Duration(milliseconds: 50);
  for (var t = Duration.zero; t < total; t += step) {
    await tester.pump(step);
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('iPad drawing and archive interaction smoke test', (
    tester,
  ) async {
    await app.main();
    await pumpFrames(tester, const Duration(seconds: 2));
    await binding.takeScreenshot('ipad-home-figma');
    final timings = <FrameTiming>[];
    void collect(List<FrameTiming> frames) => timings.addAll(frames);
    SchedulerBinding.instance.addTimingsCallback(collect);
    await tester.tap(find.text('친구 그리기 / 사진찍기'));
    await tester.pumpAndSettle();
    final canvas = find.byKey(const ValueKey('drawing-canvas'));
    expect(find.text('Drawing'), findsOneWidget);
    final rect = tester.getRect(canvas);
    await tester.timedDragFrom(
      rect.center - const Offset(180, 80),
      const Offset(340, 60),
      const Duration(milliseconds: 700),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('지우개'));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('ipad-studio-eraser');
    await tester.timedDragFrom(
      rect.center - const Offset(0, 100),
      const Offset(0, 180),
      const Duration(milliseconds: 500),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('되돌리기'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('다시 실행'));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('ipad-studio-expanded');
    await tester.tap(find.text('Take a photo'));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('ipad-studio-photo');
    await tester.tap(find.text('Drawing'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('도구 숨기기'));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('ipad-studio-focus');
    await tester.tap(find.byTooltip('도구 보이기'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('펜'));
    await tester.tap(find.byTooltip('종이 고르기'));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('ipad-studio-paper-menu');
    await tester.tap(find.text('모눈 종이'));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('ipad-studio-grid');
    await tester.tap(find.byTooltip('색상'));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('ipad-studio-colors');
    await tester.tap(find.byTooltip('색상 닫기'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('top-action-홈')));
    await pumpFrames(tester, const Duration(seconds: 1));
    await tester.tap(find.text('친구들 보러가기'));
    await tester.pumpAndSettle();
    // 뚜치 is two cards along: step to it through 네모린.
    await tester.tap(find.bySemanticsLabel(RegExp('^네모린,')));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel(RegExp('^뚜치,')));

    await tester.pumpAndSettle();
    await binding.takeScreenshot('ipad-archive-fixed');
    await tester.tap(find.text('뚜치의 집에 놀러 가기'));
    await pumpFrames(tester, const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    SchedulerBinding.instance.removeTimingsCallback(collect);
    if (timings.isNotEmpty) {
      final builds =
          timings.map((e) => e.buildDuration.inMicroseconds / 1000).toList()
            ..sort();
      final rasters =
          timings.map((e) => e.rasterDuration.inMicroseconds / 1000).toList()
            ..sort();
      binding.reportData ??= {};
      binding.reportData!['debug_simulator_frames'] = {
        'count': timings.length,
        'build_p90_ms': builds[((builds.length - 1) * 0.9).round()],
        'raster_p90_ms': rasters[((rasters.length - 1) * 0.9).round()],
        'note':
            'Debug simulator timings, not a physical-device release benchmark.',
      };
    }
  });
}
