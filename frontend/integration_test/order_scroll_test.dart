import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/data/order_repository.dart';
import 'package:bogle_app/src/models/character_friend.dart';
import 'package:bogle_app/src/screens/order_screen.dart';
import 'package:bogle_app/src/theme/bogle_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// These fixtures do not write to the iPad's store. Run with --keep-app-running:
// flutter drive otherwise uninstalls the host app and deletes its saved data.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> frames(WidgetTester tester, [int milliseconds = 600]) async {
    for (var elapsed = 0; elapsed < milliseconds; elapsed += 50) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('iPad order list scrolls without covering fixed controls', (
    tester,
  ) async {
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    final seed = (await InMemoryCharacterRepository().fetchFriends()).first;
    final friends = [
      for (var i = 0; i < 24; i++)
        CharacterFriend(
          id: 'scroll-friend-$i',
          name: '친구 $i',
          personality: seed.personality,
          favoriteThings: seed.favoriteThings,
          speechStyle: seed.speechStyle,
          assetPath: seed.assetPath,
          accentHex: seed.accentHex,
        ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildBogleTheme(),
        home: OrderScreen(
          repository: InMemoryCharacterRepository(friends: friends),
          orderRepository: InMemoryOrderRepository(),
        ),
      ),
    );
    await frames(tester, 1200);
    final grid = find.byKey(const ValueKey('order-friend-grid'));
    final heading = tester.getRect(find.text('친구 선택'));
    final summary = tester.getRect(
      find.byKey(const ValueKey('order-picked-name')),
    );
    final nextButton = tester.getRect(
      find.widgetWithText(FilledButton, '친구 0 인형 만들기'),
    );
    void fixedControls() {
      expect(tester.getRect(find.text('친구 선택')), heading);
      expect(
        tester.getRect(find.byKey(const ValueKey('order-picked-name'))),
        summary,
      );
      expect(
        tester.getRect(find.widgetWithText(FilledButton, '친구 0 인형 만들기')),
        nextButton,
      );
      expect(tester.takeException(), isNull);
    }

    await binding.takeScreenshot('order-scroll-initial');
    final drag = await tester.startGesture(tester.getCenter(grid));
    await drag.moveBy(const Offset(0, -100));
    await frames(tester, 100);
    fixedControls();
    await binding.takeScreenshot('order-scroll-during-drag');
    await drag.up();
    await frames(tester);
    final timings = <FrameTiming>[];
    void collect(List<FrameTiming> frames) => timings.addAll(frames);
    SchedulerBinding.instance.addTimingsCallback(collect);
    await tester.fling(grid, const Offset(0, -500), 1800);
    await frames(tester, 1200);
    SchedulerBinding.instance.removeTimingsCallback(collect);
    if (timings.isNotEmpty) {
      double percentile(List<double> samples) {
        samples.sort();
        return samples[((samples.length - 1) * .95).round()];
      }

      binding.reportData = {
        'scrollFrames': timings.length,
        'scrollBuildP95Ms': percentile([
          for (final frame in timings)
            frame.buildDuration.inMicroseconds / 1000,
        ]),
        'scrollRasterP95Ms': percentile([
          for (final frame in timings)
            frame.rasterDuration.inMicroseconds / 1000,
        ]),
      };
    }
    fixedControls();
    await binding.takeScreenshot('order-scroll-after-fling');

    final scrollable = find.descendant(
      of: grid,
      matching: find.byType(Scrollable),
    );
    final last = find.byKey(const ValueKey('order-friend-scroll-friend-23'));
    await tester.scrollUntilVisible(last, 200, scrollable: scrollable);
    await frames(tester);
    final endDrag = await tester.startGesture(tester.getCenter(grid));
    await endDrag.moveBy(const Offset(0, -140));
    await frames(tester, 100);
    fixedControls();
    final pulled = tester.state<ScrollableState>(scrollable).position;
    expect(
      pulled.pixels - pulled.maxScrollExtent,
      lessThan(pulled.viewportDimension * .15),
      reason: 'A quick pull at the end must not open a large blank gap.',
    );
    await binding.takeScreenshot('order-scroll-bottom-overscroll');
    await endDrag.up();
    await frames(tester, 1200);
    final endPosition = tester.state<ScrollableState>(scrollable).position;
    expect(endPosition.pixels, closeTo(endPosition.maxScrollExtent, 1));
    await tester.ensureVisible(last);
    await frames(tester);
    final position = tester.state<ScrollableState>(scrollable).position.pixels;
    await tester.tap(last);
    await frames(tester);
    expect(
      tester.state<ScrollableState>(scrollable).position.pixels,
      closeTo(position, .01),
    );
    expect(find.text('친구 23 인형 만들기'), findsOneWidget);
    await binding.takeScreenshot('order-scroll-last-friend-selected');
    await tester.tap(find.text('친구 23 인형 만들기'));
    await frames(tester);
    expect(find.byKey(const ValueKey('order-options-panel')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
