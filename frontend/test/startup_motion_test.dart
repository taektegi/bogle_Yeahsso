import 'package:bogle_app/src/widgets/startup_artwork.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> openArtwork(
    WidgetTester tester, {
    bool reduced = false,
    bool tickerEnabled = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: TickerMode(
            enabled: tickerEnabled,
            child: const StartupArtwork(),
          ),
        ),
      ),
    );
    if (!reduced) {
      await tester.runAsync(() async {
        await StartupArtwork.precacheLayers(
          tester.element(find.byType(StartupArtwork)),
        );
      });
      await tester.pump();
      await tester.pump();
    }
  }

  Offset bubbleOffset(WidgetTester tester, int index) {
    final transform = tester.widget<Transform>(
      find.byKey(ValueKey('startup-riser-$index')),
    );
    return Offset(
      transform.transform.entry(0, 3),
      transform.transform.entry(1, 3),
    );
  }

  testWidgets('the wordmark shows alone, then bubbles well up past it', (
    tester,
  ) async {
    await openArtwork(tester);
    final logo = tester.getRect(find.byKey(const ValueKey('startup-wordmark')));
    // First frame: every bubble still waits below the screen.
    for (var i = 0; i < 30; i++) {
      expect(bubbleOffset(tester, i).dy, 0);
    }
    await tester.pump(const Duration(seconds: 1));
    final risen = [
      for (var i = 0; i < 30; i++)
        if (bubbleOffset(tester, i).dy < -200) i,
    ];
    expect(risen.length, greaterThan(10));
    await tester.pump(const Duration(milliseconds: 500));
    for (final i in risen) {
      expect(bubbleOffset(tester, i).dy, lessThan(-200));
    }
    expect(
      tester.getRect(find.byKey(const ValueKey('startup-wordmark'))),
      logo,
    );
    await tester.pump(const Duration(seconds: 8));
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bubble drift pauses in background and when ticker is hidden', (
    tester,
  ) async {
    await openArtwork(tester);
    await tester.pump(const Duration(milliseconds: 400));
    final before = bubbleOffset(tester, 2);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 3));
    expect(bubbleOffset(tester, 2), before);
    expect(tester.binding.transientCallbackCount, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(bubbleOffset(tester, 2), before);
    await tester.pump(const Duration(milliseconds: 200));
    expect(bubbleOffset(tester, 2).dy, lessThan(before.dy));
    await openArtwork(tester, tickerEnabled: false);
    final hidden = bubbleOffset(tester, 2);
    await tester.pump(const Duration(seconds: 3));
    expect(bubbleOffset(tester, 2), hidden);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('reduced motion uses static artwork, including live changes', (
    tester,
  ) async {
    await openArtwork(tester, reduced: true);
    expect(find.byKey(const ValueKey('startup-riser-0')), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
    await openArtwork(tester);
    await tester.pump(const Duration(milliseconds: 500));
    expect(bubbleOffset(tester, 0).dy, lessThan(0));
    await openArtwork(tester, reduced: true);
    await tester.pump(const Duration(seconds: 2));
    expect(find.byKey(const ValueKey('startup-riser-0')), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
  });
}
