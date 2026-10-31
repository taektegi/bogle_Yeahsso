import 'dart:io';

import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/data/motion_service.dart';
import 'package:bogle_app/src/models/character_friend.dart';
import 'package:bogle_app/src/screens/friend_screen.dart';
import 'package:bogle_app/src/screens/house/house_widgets.dart';
import 'package:bogle_app/src/screens/house/figure_motion.dart';
import 'package:bogle_app/src/screens/house/motion_clip_player.dart';
import 'package:bogle_app/src/theme/bogle_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A 60 × 60 clip of four 100 ms frames; in its first frame the friend is
/// the box from (20, 10) to (40, 60), standing on the bottom edge.
final clipPath = File('test/fixtures/motion_clip.gif').absolute.path;

class _Clips implements MotionService {
  @override
  Future<Map<MotionClipKind, MotionClip>?> clipsFor(CharacterFriend friend) =>
      Future.value({
        for (final kind in [MotionClipKind.wave, MotionClipKind.jump])
          kind: MotionClip(clipPath, const Rect.fromLTRB(0, 0, 1, 1)),
      });
}

/// Early afternoon: every friend is up.
DateTime afternoon() => DateTime(2026, 9, 28, 14);

/// Lets work on the real clock (reading files, decoding frames) finish,
/// then moves the test clock on.
Future<void> settle(WidgetTester tester, {int rounds = 6}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// The house with animations on (clips only play then).
Future<CharacterFriend> openHouse(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1366, 1024);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = InMemoryCharacterRepository();
  final friend = (await repo.fetchFriends()).firstWhere(
    (f) => f.id == 'dduchi',
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: buildBogleTheme(),
      home: FriendScreen(
        repository: repo,
        friend: friend,
        clock: afternoon,
        motion: _Clips(),
      ),
    ),
  );
  // The house fades in and the friend waves hello first.
  await settle(tester, rounds: 60);
  return friend;
}

Finder get player => find.byType(MotionClipPlayer);

/// Pats the friend low on its body (its balloon may cover the middle).
Future<void> pat(WidgetTester tester) async {
  final figure = tester.getRect(find.byType(FriendFigure).first);
  await tester.tapAt(
    Offset(figure.center.dx, figure.bottom - figure.height * .2),
  );
}

bool figureShowing(WidgetTester tester) =>
    tester.widget<Opacity>(find.byKey(const ValueKey('house-figure'))).opacity >
    0;

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final f in await InMemoryCharacterRepository().fetchFriends()) {
      await anchorsFor(f.assetPath);
    }
  });

  testWidgets('a clip is read once: its length and where the friend is', (
    tester,
  ) async {
    final clip = (await tester.runAsync(() => LoadedClip.load(clipPath)))!;

    expect(clip.size, const Size(60, 60));
    expect(clip.length, const Duration(milliseconds: 400));
    expect(clip.figure, const Rect.fromLTRB(20, 10, 40, 60));
    expect(
      await tester.runAsync(() => LoadedClip.load('/no/such/clip.gif')),
      isNull,
    );
  });

  testWidgets('터치는 손 흔들기 클립에 가리지 않고 전체 동작을 한 번씩 보여 준다', (tester) async {
    await openHouse(tester);
    await settle(tester, rounds: 8);
    final seen = <Act>{};
    for (var i = 0; i < patActs.length; i++) {
      await pat(tester);
      await tester.pump();
      final dynamic state = tester.state(find.byType(LivingCharacter).first);
      seen.add(state.debugAct as Act);
      expect(player, findsNothing);
      expect(figureShowing(tester), isTrue);
    }
    expect(seen, containsAll(patActs));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a snack given while a clip plays ends it: the friend eats', (
    tester,
  ) async {
    await openHouse(tester);
    await tester.tap(find.text('간식주기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.bySemanticsLabel(RegExp('^도토리 주기')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(seconds: 3));
    await settle(tester, rounds: 2);
    expect(figureShowing(tester), isFalse);

    await tester.tap(find.text('간식주기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.bySemanticsLabel(RegExp('^쿠키 주기')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(player, findsNothing);
    expect(figureShowing(tester), isTrue);
    expect(find.byKey(const ValueKey('house-snack')), findsOneWidget);
    await settle(tester, rounds: 4);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a pat while eating doesn\'t hide the friend behind a clip', (
    tester,
  ) async {
    await openHouse(tester);
    await tester.tap(find.text('간식주기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.bySemanticsLabel(RegExp('^쿠키 주기')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byKey(const ValueKey('house-snack')), findsOneWidget);

    await pat(tester);
    await settle(tester, rounds: 2);

    expect(player, findsNothing);
    expect(figureShowing(tester), isTrue);
    expect(find.byKey(const ValueKey('house-snack')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
