import 'dart:ui';
import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/screens/create_studio_screen.dart';
import 'package:bogle_app/src/theme/bogle_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('profile studio toolbar on physical iPad', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildBogleTheme(),
        home: CreateStudioScreen(repository: InMemoryCharacterRepository()),
      ),
    );
    Future<void> rest() async {
      // Real vsync, not a 16 ms test pump loop that would impose a 60 Hz clock.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 420)),
      );
      await tester.pump();
    }

    await rest();
    final canvas = tester.getRect(find.byKey(const ValueKey('drawing-canvas')));
    for (var i = 0; i < 30; i++) {
      await tester.dragFrom(
        canvas.center + Offset(-180, i * 3.0),
        const Offset(260, 30),
      );
    }
    await rest();
    final frames = <FrameTiming>[];
    void record(List<FrameTiming> values) => frames.addAll(values);
    Future<void> cycle() async {
      for (final label in ['지우개', '펜', '도구 숨기기', '도구 보이기']) {
        await tester.tap(find.byTooltip(label));
        await rest();
      }
    }

    await cycle();
    final before = tester.getRect(find.byTooltip('친구로 만들기'));
    await tester.tap(find.byTooltip('도구 숨기기'));
    await rest();
    final collapsed = tester.getRect(find.byTooltip('친구로 만들기'));
    await tester.tap(find.byTooltip('도구 보이기'));
    await rest();
    SchedulerBinding.instance.addTimingsCallback(record);
    try {
      for (var i = 0; i < 8; i++) {
        await cycle();
      }
      await rest();
    } finally {
      SchedulerBinding.instance.removeTimingsCallback(record);
    }
    double percentile(List<double> values, double p) {
      values.sort();
      return values.isEmpty ? 0 : values[((values.length - 1) * p).round()];
    }

    final build = frames
        .map((f) => f.buildDuration.inMicroseconds / 1000)
        .toList();
    final raster = frames
        .map((f) => f.rasterDuration.inMicroseconds / 1000)
        .toList();
    final intervals = <double>[];
    for (var i = 1; i < frames.length; i++) {
      final ms =
          (frames[i].timestampInMicroseconds(FramePhase.vsyncStart) -
              frames[i - 1].timestampInMicroseconds(FramePhase.vsyncStart)) /
          1000;
      if (ms > 0 && ms < 30) intervals.add(ms);
    }
    binding.reportData = {
      'scenario':
          '30 strokes, 8 cycles of eraser/pen/hide/show; real iPad profile',
      'frames': frames.length,
      'displayReportedHz': tester.view.display.refreshRate,
      'buildP95Ms': percentile(build, .95),
      'rasterP95Ms': percentile(raster, .95),
      'buildMaxMs': percentile(build, 1),
      'rasterMaxMs': percentile(raster, 1),
      'framesOver8_33Ms': frames
          .where(
            (f) =>
                f.buildDuration.inMicroseconds > 8333 ||
                f.rasterDuration.inMicroseconds > 8333,
          )
          .length,
      'framesOver16_67Ms': frames
          .where(
            (f) =>
                f.buildDuration.inMicroseconds > 16667 ||
                f.rasterDuration.inMicroseconds > 16667,
          )
          .length,
      'activeVsyncIntervalMedianMs': percentile(intervals, .5),
      'doneCenterJumpPt': (collapsed.center - before.center).distance,
      'doneWidthChangePt': collapsed.width - before.width,
    };
    expect(frames, isNotEmpty);
    expect(tester.takeException(), isNull);
  });
}
