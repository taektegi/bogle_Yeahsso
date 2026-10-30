import 'package:bogle_app/src/data/character_generation.dart';
import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/screens/setup_friend_screen.dart';
import 'package:bogle_app/src/theme/bogle_theme.dart';
import 'package:bogle_app/src/widgets/friend_arrival.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final character = find.byKey(const ValueKey('arrival-character'));
final leftCloud = find.byKey(const ValueKey('arrival-cloud-left'));

Future<void> open(WidgetTester tester, {bool reduced = false}) async {
  tester.view.physicalSize = const Size(1366, 1024);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildBogleTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
        child: child!,
      ),
      home: SetupFriendScreen(
        art: const GeneratedArt(assetPath: 'assets/figma/character_friend.svg'),
        repository: InMemoryCharacterRepository(),
      ),
    ),
  );
}

void main() {
  for (final size in [
    const Size(1024, 768),
    const Size(1194, 834),
    const Size(1366, 1024),
  ]) {
    testWidgets('birth rises, overshoots, and settles on $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      Future<void> frame(double value) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: size.width - 56,
                height: size.height - 300,
                child: FriendArrival(
                  progress: AlwaysStoppedAnimation(value),
                  child: const SizedBox(width: 380, height: 220),
                ),
              ),
            ),
          ),
        ),
      );
      await frame(0);
      expect(tester.getTopLeft(character).dy, greaterThan(size.height));
      expect(tester.getTopLeft(leftCloud).dy, greaterThan(size.height));
      await frame(.49);
      final crest = tester.getCenter(character).dy;
      final risingCloud = tester.getCenter(leftCloud);
      await frame(.66);
      final landing = tester.getCenter(character).dy;
      await frame(1);
      final rest = tester.getRect(character);
      expect(crest, lessThan(rest.center.dy - 40));
      expect(landing, greaterThan(rest.center.dy));
      expect(rest.top, greaterThan(0));
      expect(rest.bottom, lessThan(size.height));
      expect(tester.getCenter(leftCloud).dx, lessThan(risingCloud.dx));
      expect(tester.getCenter(leftCloud).dy, lessThan(risingCloud.dy));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('arrival finishes once and stays finished on the next question', (
    tester,
  ) async {
    await open(tester);
    expect(tester.getTopLeft(character).dy, greaterThan(1024));
    await tester.pump(FriendArrival.duration);
    await tester.pumpAndSettle();
    // The first question follows on its own.
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();
    expect(find.text('이 친구에 대해 알려주세요! 이 친구의 이름은 뭐예요?'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('a tap mid-arrival finishes it and moves on', (tester) async {
    await open(tester);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tapAt(const Offset(300, 700));
    await tester.pumpAndSettle();
    expect(find.text('이 친구에 대해 알려주세요! 이 친구의 이름은 뭐예요?'), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('background pauses arrival and leaving disposes its ticker', (
    tester,
  ) async {
    await open(tester);
    await tester.pump(const Duration(milliseconds: 650));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    final paused = tester.getCenter(character);
    await tester.pump(const Duration(seconds: 5));
    expect(tester.getCenter(character), paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(tester.getCenter(character), isNot(paused));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('reduced motion shows a settled friend immediately', (
    tester,
  ) async {
    await open(tester, reduced: true);
    await tester.pumpAndSettle();
    expect(tester.getRect(character).bottom, lessThan(1024));
    expect(tester.binding.transientCallbackCount, 0);
    // The first question follows on its own.
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();
    expect(find.text('이 친구에 대해 알려주세요! 이 친구의 이름은 뭐예요?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
