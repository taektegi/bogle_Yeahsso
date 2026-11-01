import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/data/chat_service.dart';
import 'package:bogle_app/src/models/character_friend.dart';
import 'package:bogle_app/src/models/friend_status.dart';
import 'package:bogle_app/src/screens/friend_screen.dart';
import 'package:bogle_app/src/theme/bogle_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

class _Chat implements ChatService {
  int _turn = 0;
  static const _replies = [
    '오늘은 창밖 구름을 구경했어! 토끼 모양 구름도 있었어.',
    '나는 알록달록 크레파스가 제일 좋아. 너는 어떤 색이 좋아?',
    '좋아! 우리 같이 숨바꼭질하자. 내가 먼저 숨을게!',
  ];
  @override
  Future<String?> replyTo(CharacterFriend friend, String text) async =>
      _replies[_turn++ % _replies.length];
  @override
  Future<List<ChatLine>> history(CharacterFriend friend) async => const [];
}

/// 실제 iPad 화면에서 대화창을 열고 몇 마디 나눈 모습을 남긴다.
/// 기기 데이터에 연결하지 않는 세션 전용 저장소를 쓴다.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  Future<void> frames(WidgetTester tester, int milliseconds) async {
    for (var t = 0; t < milliseconds; t += 50) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(tester.takeException(), isNull);
  }

  testWidgets('실제 iPad: 친구 집 대화창', (tester) async {
    final repo = InMemoryCharacterRepository();
    final friends = await repo.fetchFriends();
    await repo.saveStatus(
      friends.first.id,
      FriendStatus(fullness: 60, updatedAt: DateTime.now()),
    );
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildBogleTheme(),
        home: FriendScreen(
          repository: repo,
          friend: friends.first,
          chat: _Chat(),
          clock: () => DateTime(2026, 10, 29, 14),
        ),
      ),
    );
    await frames(tester, 2500);
    await tester.tap(find.bySemanticsLabel('대화하기'));
    await frames(tester, 900);
    await binding.takeScreenshot('chat-open');
    await tester.tap(find.widgetWithText(ActionChip, '오늘 뭐 했어?'));
    await frames(tester, 1500);
    await tester.tap(find.widgetWithText(ActionChip, '뭘 좋아해?'));
    await frames(tester, 1500);
    await tester.enterText(
      find.byKey(const ValueKey('house-chat-field')),
      '같이 놀자',
    );
    await tester.pump();
    await tester.tap(find.byTooltip('보내기'));
    await frames(tester, 1500);
    await binding.takeScreenshot('chat-talking');
    await tester.pumpWidget(const SizedBox());
  }, timeout: const Timeout(Duration(minutes: 2)));
}
