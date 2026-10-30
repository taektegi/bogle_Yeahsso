import 'dart:ui' as ui;

import 'package:bogle_app/src/app.dart';
import 'package:bogle_app/src/data/app_services.dart';
import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/data/order_repository.dart';
import 'package:bogle_app/src/models/character_friend.dart';
import 'package:bogle_app/src/screens/loading_screen.dart';
import 'package:bogle_app/src/screens/setup_friend_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// In-memory fixtures keep the real iPad's saved friends and profile intact.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  Future<void> frames(WidgetTester tester, [int milliseconds = 1200]) async {
    for (var elapsed = 0; elapsed < milliseconds; elapsed += 50) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> capture(WidgetTester tester, String name) async {
    await frames(tester);
    expect(tester.takeException(), isNull, reason: name);
    debugPrint('Release screen verified: $name');
    await binding.takeScreenshot('release-$name');
  }

  testWidgets(
    'iPad frontend: home, archive, house, profile, order, studio and setup',
    (tester) async {
      tester.testTextInput.register();
      addTearDown(tester.testTextInput.unregister);
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      final initial = await InMemoryCharacterRepository().fetchFriends();
      final friends = InMemoryCharacterRepository(
        friends: [
          for (final friend in initial)
            friend.copyWith(
              sleep: const SleepSchedule(bedtime: 0, wakeTime: 0),
            ),
        ],
      );
      final orders = InMemoryOrderRepository(
        addresses: const [
          DeliveryAddress(
            label: '우리 집',
            recipient: '김보글',
            phone: '010-0000-0000',
            zip: '12345',
            street: '서울 보글로 1',
          ),
        ],
      );
      await tester.pumpWidget(
        BogleApp(
          services: AppServices.local(characters: friends, orders: orders),
        ),
      );
      await frames(tester, 5500);
      await capture(tester, 'home');
      await tester.tap(find.text('친구들 보러가기'));
      await frames(tester, 800);
      await capture(tester, 'archive');
      await tester.tap(find.text('뭉글이의 집에 놀러 가기'));
      await frames(tester, 2000);
      await capture(tester, 'house');
      await tester.tap(find.bySemanticsLabel('대화하기'));
      await frames(tester, 800);
      await tester.enterText(
        find.byKey(const ValueKey('house-chat-field')),
        '오늘 뭐 했어?',
      );
      await tester.tap(find.byTooltip('보내기'));
      FocusManager.instance.primaryFocus?.unfocus();
      await frames(tester, 1000);
      expect(await friends.fetchMemories('mungle'), contains('오늘 뭐 했어?'));
      await capture(tester, 'chat');
      await tester.tap(find.byTooltip('대화 닫기'));
      await frames(tester, 800);
      await tester.tap(find.bySemanticsLabel('간식주기'));
      await frames(tester, 800);
      await capture(tester, 'snacks');

      await tester.tap(find.byKey(const ValueKey('top-action-홈')));
      await frames(tester);
      await tester.tap(find.byKey(const ValueKey('top-action-마이페이지')));
      await frames(tester, 800);
      await capture(tester, 'profile');
      final scrollable = find
          .descendant(
            of: find.byKey(const ValueKey('profile-scroll')),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('고객센터'),
        250,
        scrollable: scrollable,
      );
      await frames(tester, 800);
      await tester.tap(find.text('고객센터'));
      await frames(tester, 800);
      await tester.tap(find.text('그림과 프로필은 저장되나요?'));
      await frames(tester, 800);
      await capture(tester, 'storage-guide');
      await tester.tap(find.text('닫기'));
      await frames(tester, 800);
      await tester.tap(find.byKey(const ValueKey('top-action-홈')));
      await frames(tester);

      await tester.tap(find.text('주문하기'));
      await frames(tester, 800);
      await capture(tester, 'order-pick');
      await tester.tap(find.text('뭉글이 인형 만들기'));
      await frames(tester, 800);
      await capture(tester, 'order-options');
      await tester.ensureVisible(find.text('주문하기'));
      await tester.tap(find.text('주문하기'));
      await frames(tester, 800);
      await capture(tester, 'order-checkout');
      await tester.ensureVisible(find.text('보호자가 주문 내용을 확인했고, 결제에 동의해요'));
      await tester.tap(find.text('보호자가 주문 내용을 확인했고, 결제에 동의해요'));
      await tester.pump();
      final pay = find.widgetWithText(FilledButton, '32,000원 결제하기');
      await tester.ensureVisible(pay);
      await tester.tap(pay);
      await frames(tester, 7000);
      await capture(tester, 'order-done');
      await tester.ensureVisible(find.text('주문 현황 보기'));
      await tester.tap(find.text('주문 현황 보기'));
      await frames(tester, 800);
      await capture(tester, 'order-history');
      await tester.tap(find.text('닫기'));
      await frames(tester, 800);
      await tester.tap(find.byKey(const ValueKey('top-action-홈')));
      await frames(tester);

      await tester.tap(find.text('친구 그리기 / 사진찍기'));
      await frames(tester, 800);
      final canvas = find.byKey(const ValueKey('drawing-canvas'));
      final start = tester.getCenter(canvas);
      final pencil = await tester.startGesture(
        start,
        kind: ui.PointerDeviceKind.stylus,
      );
      await pencil.moveTo(start + const Offset(140, 70));
      await pencil.up();
      await frames(tester, 800);
      await capture(tester, 'drawing');
      await tester.tap(find.byTooltip('색상'));
      await frames(tester, 800);
      await capture(tester, 'colors');
      await tester.tap(find.byTooltip('색상 닫기'));
      await frames(tester, 800);
      await tester.tap(find.byTooltip('친구로 만들기'));
      await frames(tester, 700);
      if (find.byType(LoadingScreen).evaluate().isNotEmpty) {
        await capture(tester, 'loading');
      }
      for (
        var i = 0;
        i < 100 && find.byType(SetupFriendScreen).evaluate().isEmpty;
        i++
      ) {
        await frames(tester, 100);
      }
      expect(find.byType(SetupFriendScreen), findsOneWidget);
      await frames(tester, 3000);
      final arrival = find.bySemanticsLabel('눌러서 다음으로');
      if (arrival.evaluate().isNotEmpty) {
        await tester.tap(arrival);
        await frames(tester, 1000);
      }
      await capture(tester, 'setup-name');
      await tester.tap(find.text('글자로 적기'));
      await frames(tester, 800);
      await tester.enterText(
        find.byKey(const ValueKey('setup-answer')),
        '릴리스친구',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, '다음'));
      await frames(tester, 800);
      await capture(tester, 'setup-personality');
      // The rest is chosen, each followed by 다음.
      await tester.tap(find.text('다정한 응원가'));
      await tester.pump();
      await tester.tap(find.text('다음'));
      await frames(tester, 800);
      await tester.tap(find.text('구름 구경하기'));
      await tester.pump();
      await tester.tap(find.text('다음'));
      await frames(tester, 800);
      await tester.tap(find.text('공손하고 부드럽게'));
      await frames(tester, 800);
      await tester.tap(find.text('이 말투로 정하기'));
      await frames(tester, 3000);
      await capture(tester, 'friend-created');
      expect((await friends.fetchFriends()).last.name, '릴리스친구');
    },
  );
}
