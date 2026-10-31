import 'dart:async';
import 'dart:ui';
import 'package:bogle_app/main.dart' as app;
import 'package:bogle_app/src/data/character_generation.dart';
import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/screens/loading_screen.dart';
import 'package:bogle_app/src/screens/setup_friend_screen.dart';
import 'package:bogle_app/src/theme/bogle_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const newArt = GeneratedArt(assetPath: 'assets/figma/character_friend.svg');

class HeldGeneration implements CharacterGenerationJob {
  final done = Completer<GeneratedArt>();
  @override
  Future<GeneratedArt> get result => done.future;
  @override
  void cancel() {}
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('iPad logo reveal, draft return and demo completion', (
    tester,
  ) async {
    await app.main();
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.text('친구 그리기 / 사진찍기'));
    await tester.pumpAndSettle();
    final canvas = find.byKey(const ValueKey('drawing-canvas'));
    final pencil = await tester.startGesture(
      tester.getCenter(canvas),
      kind: PointerDeviceKind.stylus,
    );
    for (var i = 0; i < 6; i++) {
      await pencil.moveBy(const Offset(30, 10));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await pencil.up();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byTooltip('친구로 만들기'));
    await tester.pump(const Duration(milliseconds: 950));
    await binding.takeScreenshot('ipad-loading-reveal-start');
    await tester.pump(const Duration(milliseconds: 950));
    await binding.takeScreenshot('ipad-loading-reveal-middle');
    await tester.pump(const Duration(seconds: 3));
    await binding.takeScreenshot('ipad-loading-calm');
    await tester.tap(
      find.byKey(const ValueKey('bubble-4')),
      warnIfMissed: false,
    );
    await tester.pump(const Duration(milliseconds: 250));
    await binding.takeScreenshot('ipad-loading-bubble-split');
    await tester.pump(const Duration(milliseconds: 900));
    await binding.takeScreenshot('ipad-loading-bubble-split-after');
    await tester.tap(find.text('그림으로 돌아가기'));
    await tester.pumpAndSettle();
    expect(canvas, findsOneWidget);
    await binding.takeScreenshot('ipad-loading-draft-retained');
    await tester.tap(find.byTooltip('친구로 만들기'));
    await tester.pump(const Duration(seconds: 19));
    await tester.pumpAndSettle();
    expect(find.byType(SetupFriendScreen), findsOneWidget);
    expect(
      tester
          .widget<SetupFriendScreen>(find.byType(SetupFriendScreen))
          .input
          ?.image,
      isNotEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'iPad long wait keeps looping past one cycle without navigation',
    (tester) async {
      final job = HeldGeneration();
      final timings = <FrameTiming>[];
      void collect(List<FrameTiming> frames) => timings.addAll(frames);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildBogleTheme(),
          home: LoadingScreen(
            repository: InMemoryCharacterRepository(),
            startGeneration: () => job,
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 4));
      SchedulerBinding.instance.addTimingsCallback(collect);
      await tester.pump(const Duration(seconds: 28));
      SchedulerBinding.instance.removeTimingsCallback(collect);
      expect(find.textContaining('시간이 조금 더'), findsOneWidget);
      expect(find.byType(SetupFriendScreen), findsNothing);
      await binding.takeScreenshot('ipad-loading-long-wait');
      final build =
          timings.map((f) => f.buildDuration.inMicroseconds / 1000).toList()
            ..sort();
      final raster =
          timings.map((f) => f.rasterDuration.inMicroseconds / 1000).toList()
            ..sort();
      binding.reportData ??= {};
      binding.reportData!.addAll({
        'scenario':
            'loading animation on iPad Simulator (debug, not hardware FPS)',
        'frames': timings.length,
        if (build.isNotEmpty) 'buildP95Ms': build[(build.length * .95).floor()],
        if (raster.isNotEmpty)
          'rasterP95Ms': raster[(raster.length * .95).floor()],
      });
      job.done.complete(newArt);
      await tester.pumpAndSettle();
      expect(find.byType(SetupFriendScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
