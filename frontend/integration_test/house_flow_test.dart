import 'package:bogle_app/src/app.dart';
import 'package:bogle_app/src/data/app_services.dart';
import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/models/character_friend.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  Future<void> capture(WidgetTester tester, String name) async {
    await tester.pump(const Duration(milliseconds: 900));
    await binding.takeScreenshot(name);
  }

  testWidgets('archive carousel, a friend\'s house, snacks, chat, a guest', (
    tester,
  ) async {
    // A daytime interaction test must not randomly become a sleep test at
    // night. Only this fixture's friends have their bedtime disabled.
    final repository = InMemoryCharacterRepository();
    for (final friend in await repository.fetchFriends()) {
      await repository.saveFriend(
        friend.copyWith(sleep: const SleepSchedule(bedtime: 0, wakeTime: 0)),
      );
    }
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await tester.pumpWidget(
      BogleApp(services: AppServices.local(characters: repository)),
    );
    // Home and the house idle-animate, so pump instead of settling.
    await tester.pump(const Duration(seconds: 5));
    await tester.tap(find.text('친구들 보러가기'));
    await tester.pump(const Duration(seconds: 1));
    await capture(tester, 'ipad-archive');

    await tester.tap(find.text('뭉글이의 집에 놀러 가기'));
    await tester.pump(const Duration(seconds: 1));
    await capture(tester, 'ipad-house');

    await tester.tap(find.bySemanticsLabel('간식주기'));
    await capture(tester, 'ipad-house-snack');

    await tester.tap(find.bySemanticsLabel('대화하기'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.widgetWithText(ActionChip, '뭘 좋아해?'));
    await tester.pump(const Duration(milliseconds: 700));
    await capture(tester, 'ipad-house-chat');
    await tester.tap(find.byTooltip('대화 닫기'));
    await tester.pump(const Duration(milliseconds: 400));

    // A friend comes over, hopping in from the right, and goes home.
    await tester.tap(find.bySemanticsLabel('초대하기'));
    await tester.pump(const Duration(milliseconds: 500));
    await capture(tester, 'ipad-house-invite');
    await tester.tap(find.bySemanticsLabel('뚜치 초대하기'));
    await tester.pump(const Duration(milliseconds: 1200));
    await capture(tester, 'ipad-house-guest-arriving');
    await tester.pump(const Duration(seconds: 2));
    await capture(tester, 'ipad-house-guest');
    await tester.tap(find.bySemanticsLabel('배웅하기'));
    // The spring simulation caps a single frame's elapsed time. Pump real
    // frames through both the goodbye wave and the subsequent travel cue.
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.bySemanticsLabel('초대하기').evaluate().isNotEmpty) break;
    }
    await capture(tester, 'ipad-house-guest-departed');
    expect(find.bySemanticsLabel('초대하기'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('house-back')));
    await tester.pump(const Duration(seconds: 1));
    await tester.drag(
      find.byKey(const ValueKey('archive-carousel')),
      const Offset(-420, 0),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('뚜치의 집에 놀러 가기'));
    await capture(tester, 'ipad-house-next');

    await tester.tap(find.byKey(const ValueKey('top-action-홈')));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('주문하기'));
    await tester.pump(const Duration(seconds: 1));
    await capture(tester, 'ipad-order');
    await tester.tap(find.byKey(const ValueKey('top-action-홈')));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('친구들 보러가기'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
