import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/data/chat_service.dart';
import 'package:bogle_app/src/models/character_friend.dart';
import 'package:bogle_app/src/models/friend_status.dart';
import 'package:bogle_app/src/screens/friend_screen.dart';
import 'package:bogle_app/src/screens/house/figure_motion.dart';
import 'package:bogle_app/src/screens/house/house_widgets.dart';
import 'package:bogle_app/src/screens/house/chat_panel.dart';
import 'package:bogle_app/src/theme/bogle_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

class _Chat implements ChatService {
  @override
  Future<String?> replyTo(CharacterFriend friend, String text) async =>
      '너랑 같이 구름을 구경하고 싶어. 우리 친구들과 함께 그림을 그리면 정말 재미있을 것 같아! 다음에는 네가 좋아하는 놀이도 알려 줘.';
  @override
  Future<List<ChatLine>> history(CharacterFriend friend) async => const [];
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  Future<void> frames(WidgetTester tester, int milliseconds) async {
    for (var t = 0; t < milliseconds; t += 50) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(tester.takeException(), isNull);
  }

  testWidgets('실제 iPad: 32종 터치·함께 서기·간식·대화·배웅', (tester) async {
    // 실제 기기 데이터에 연결하지 않는 세션 전용 저장소다.
    final repo = InMemoryCharacterRepository();
    final friends = await repo.fetchFriends();
    for (final friend in friends) {
      await repo.saveStatus(
        friend.id,
        FriendStatus(fullness: 30, updatedAt: DateTime.now()),
      );
    }
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildBogleTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: false),
          child: child!,
        ),
        home: FriendScreen(
          repository: repo,
          friend: friends.first,
          chat: _Chat(),
          clock: () => DateTime(2026, 10, 29, 14),
        ),
      ),
    );
    await frames(tester, 1800);
    final alone = tester.getRect(find.bySemanticsLabel('뭉글이 쓰다듬기'));
    final seen = <Act>{};
    for (var i = 0; i < patActs.length; i++) {
      await tester.tap(find.bySemanticsLabel('뭉글이 쓰다듬기'));
      await tester.pump();
      final dynamic state = tester.state(find.byType(LivingCharacter).first);
      seen.add(state.debugAct as Act);
      await frames(tester, 100);
    }
    expect(seen, containsAll(patActs));
    await frames(tester, 4000);
    await tester.tap(find.bySemanticsLabel('초대하기'));
    await frames(tester, 500);
    await tester.tap(find.bySemanticsLabel('뚜치 초대하기'));
    await frames(tester, 3600);
    final guest = tester.getRect(find.byKey(const ValueKey('house-guest')));
    final host = tester.getRect(find.bySemanticsLabel('뭉글이 쓰다듬기'));
    expect(guest.left, greaterThan(host.right));
    expect(guest.width / host.width, closeTo(.9, .01));
    await binding.takeScreenshot('company');
    await tester.tap(find.bySemanticsLabel('간식주기'));
    await frames(tester, 500);
    await tester.tap(find.bySemanticsLabel(RegExp('^쿠키 주기')));
    await frames(tester, 1100);
    expect(find.byKey(const ValueKey('house-snack')), findsOneWidget);
    expect(find.byKey(const ValueKey('guest-snack')), findsOneWidget);
    await binding.takeScreenshot('shared-snack');
    await frames(tester, 3400);
    expect((await repo.fetchStatus('mungle')).fullness, 52);
    expect((await repo.fetchStatus('dduchi')).fullness, 52);
    await tester.tap(find.bySemanticsLabel('대화하기'));
    await frames(tester, 600);
    await tester.tap(find.widgetWithText(ActionChip, '오늘 뭐 했어?'));
    await frames(tester, 1200);
    final chatPanel = find.byType(ChatPanel);
    Finder chatSays(String part) => find.descendant(
      of: chatPanel,
      matching: find.byWidgetPredicate(
        (w) => w is Text && (w.semanticsLabel ?? '').contains(part),
      ),
    );
    expect(chatSays('구름'), findsOneWidget);
    await binding.takeScreenshot('chat-dialogue');
    await tester.tap(find.byKey(const ValueKey('house-chat-field')));
    await frames(tester, 700);
    await binding.takeScreenshot('keyboard');
    await tester.enterText(
      find.byKey(const ValueKey('house-chat-field')),
      '같이 놀자',
    );
    await tester.pump();
    await tester.tap(find.byTooltip('보내기'));
    await frames(tester, 1000);
    expect(chatSays('같이 놀자'), findsWidgets);
    await tester.tap(find.byTooltip('대화 닫기'));
    await frames(tester, 500);
    await tester.tap(find.bySemanticsLabel('배웅하기'));
    // 손 흔들기(2.7초) 뒤 이동 거리에 따른 퇴장 동작이 이어진다.
    for (
      var wait = 0;
      wait < 12000 &&
          find.byKey(const ValueKey('house-guest')).evaluate().isNotEmpty;
      wait += 250
    ) {
      await frames(tester, 250);
    }
    expect(find.byKey(const ValueKey('house-guest')), findsNothing);
    await frames(tester, 600); // 주인이 중앙으로 돌아오는 자리 이동까지.
    expect(
      tester.getRect(find.bySemanticsLabel('뭉글이 쓰다듬기')).center.dx,
      closeTo(alone.center.dx, 1),
    );
    await binding.takeScreenshot('returned-to-center');
    binding.reportData = {
      ...?binding.reportData,
      'touchMotions': seen.map((act) => act.name).toList(),
      'sharedFullness': [52, 52],
    };
    await tester.pumpWidget(const SizedBox());
  }, timeout: const Timeout(Duration(minutes: 4)));
}
