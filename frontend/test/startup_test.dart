import 'dart:async';
import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/screens/home_screen.dart';
import 'package:bogle_app/src/screens/startup_screen.dart';
import 'package:bogle_app/src/theme/bogle_theme.dart';
import 'package:bogle_app/src/widgets/startup_artwork.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> openStartup(
  WidgetTester tester, {
  Future<void> Function(BuildContext)? prepare,
  bool reduced = false,
  Size size = const Size(1194, 834),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildBogleTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
        child: child!,
      ),
      home: StartupScreen(
        repository: InMemoryCharacterRepository(),
        prepare: prepare ?? (_) async {},
      ),
    ),
  );
  if (!reduced) {
    // Decode real image assets outside the fake timer clock before advancing
    // the launch timeline, so the motion fallback timeout is not artificial.
    await tester.runAsync(() async {
      await StartupArtwork.precacheLayers(
        tester.element(find.byType(StartupArtwork)),
      );
    });
    await tester.pump();
  }
}

Future<void> finishLaunch(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 1500));
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(seconds: 2));
  await tester.pump(const Duration(seconds: 1));
}

/// The start screen stays as home's shell; what goes is its overlay.
final startupOverlay = find.byKey(const ValueKey('startup-overlay'));

void main() {
  for (final size in const [
    Size(1194, 834),
    Size(1366, 1024),
    Size(1024, 768),
  ]) {
    testWidgets('startup fills landscape $size without generation copy', (
      tester,
    ) async {
      await openStartup(tester, size: size);
      expect(find.byType(StartupArtwork), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const ValueKey('startup-artwork'))),
        size,
      );
      expect(find.textContaining('친구가 찾아오는'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pump(const Duration(milliseconds: 1000));
      // Home may already be built underneath; the start screen still covers it.
      expect(startupOverlay, findsOneWidget);
      expect(find.byKey(const ValueKey('flying-wordmark')), findsNothing);
      await finishLaunch(tester);
      expect(startupOverlay, findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('preparation gates home and startup is replaced', (tester) async {
    final prepared = Completer<void>();
    await openStartup(tester, prepare: (_) => prepared.future);
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(HomeScreen), findsNothing);
    prepared.complete();
    await tester.pump();
    await finishLaunch(tester);
    expect(
      Navigator.of(tester.element(find.byType(HomeScreen))).canPop(),
      isFalse,
    );
    await tester.tap(find.text('친구 그리기 / 사진찍기'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('top-action-홈')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(startupOverlay, findsNothing);
  });
  testWidgets('background pauses startup; resume advances once', (
    tester,
  ) async {
    await openStartup(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 5));
    // Paused: the hand-over hasn't started, the start screen still shows.
    expect(startupOverlay, findsOneWidget);
    expect(find.byKey(const ValueKey('flying-wordmark')), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await finishLaunch(tester);
    expect(find.byType(HomeScreen), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(startupOverlay, findsNothing);
  });
  testWidgets('reduced motion skips decorative wait and fade', (tester) async {
    await openStartup(tester, reduced: true);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);
  });
  testWidgets('failed or stalled preparation cannot trap launch', (
    tester,
  ) async {
    await openStartup(
      tester,
      prepare: (_) => throw StateError('asset failure'),
    );
    await finishLaunch(tester);
    expect(find.byType(HomeScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    final stalled = Completer<void>();
    await openStartup(tester, prepare: (_) => stalled.future);
    await tester.pump(const Duration(seconds: 5));
    await finishLaunch(tester);
    expect(find.byType(HomeScreen), findsOneWidget);
    stalled.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
  testWidgets('dispose prevents late navigation', (tester) async {
    final prepared = Completer<void>();
    await openStartup(tester, prepare: (_) => prepared.future);
    await tester.pumpWidget(const MaterialApp(home: Text('replacement')));
    prepared.complete();
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('replacement'), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final size in const [Size(1366, 1024), Size(1024, 768)]) {
    testWidgets('the wordmark glides without a jump on $size', (tester) async {
      await openStartup(tester, size: size);
      final startup = find.byKey(const ValueKey('startup-wordmark'));
      final flying = find.byKey(const ValueKey('flying-wordmark'));
      final brand = find.byKey(const ValueKey('home-brand'));
      await tester.pump(const Duration(milliseconds: 1300));
      final resting = tester.getRect(startup);
      while (flying.evaluate().isEmpty) {
        await tester.pump(const Duration(milliseconds: 8));
      }
      // Picks up exactly where the start screen's wordmark was drawn,
      // at its scaled-to-fit size.
      var last = tester.getRect(flying);
      expect(
        last.topLeft,
        offsetMoreOrLessEquals(resting.topLeft, epsilon: .5),
      );
      expect(last.width, closeTo(resting.width, .5));
      // Then moves a little every frame, never in a jolt, and hands over
      // to home's own logo exactly where it lands.
      while (flying.evaluate().isNotEmpty) {
        await tester.pump(const Duration(milliseconds: 8));
        final now = flying.evaluate().isEmpty
            ? tester.getRect(brand)
            : tester.getRect(flying);
        expect((now.center - last.center).distance, lessThan(12));
        expect((now.width - last.width).abs(), lessThan(4));
        last = now;
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'hand-over: bubbles leave, the wordmark flies to home, home blooms',
    (tester) async {
      await openStartup(tester);
      // Bubbles well up from below and fill the page while it waits.
      await tester.pump(const Duration(milliseconds: 1300));
      final risen = tester
          .widgetList<Transform>(
            find.byWidgetPredicate(
              (w) =>
                  w is Transform &&
                  w.key is ValueKey<String> &&
                  (w.key! as ValueKey<String>).value.startsWith(
                    'startup-riser',
                  ),
            ),
          )
          .where((t) => t.transform.entry(1, 3) < -300)
          .length;
      expect(risen, greaterThan(15));

      // Hand-over starts: home is built underneath, its cards still hidden.
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      final brand = tester.getRect(find.byKey(const ValueKey('home-brand')));
      final flying = find.byKey(const ValueKey('flying-wordmark'));
      expect(flying, findsOneWidget);
      final early = tester.getRect(flying);
      expect(early.width, greaterThan(brand.width));
      Opacity playCard() => tester.widget<Opacity>(
        find
            .ancestor(of: find.text('친구들 보러가기'), matching: find.byType(Opacity))
            .last,
      );
      expect(playCard().opacity, lessThan(.2));

      // Midway: the wordmark has shrunk and moved toward the corner.
      await tester.pump(const Duration(milliseconds: 500));
      final mid = tester.getRect(flying);
      expect(mid.width, lessThan(early.width));
      expect(
        (mid.center - brand.center).distance,
        lessThan((early.center - brand.center).distance),
      );

      // Landed and bloomed: home is fully there and the overlay has gone.
      await tester.pump(const Duration(seconds: 2));
      expect(flying, findsNothing);
      expect(startupOverlay, findsNothing);
      expect(find.text('친구들 보러가기'), findsOneWidget);
      expect(
        find.ancestor(
          of: find.text('친구들 보러가기'),
          matching: find.byType(ImageFiltered),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
