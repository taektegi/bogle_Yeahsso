import 'dart:convert';
import 'dart:io';

import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/data/chat_service.dart';
import 'package:bogle_app/src/models/character_friend.dart';
import 'package:bogle_app/src/models/friend_status.dart';
import 'package:bogle_app/src/screens/friend_screen.dart';
import 'package:bogle_app/src/screens/house/scene_speech.dart';
import 'package:bogle_app/src/theme/bogle_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

class _Chat implements ChatService {
  int _turn = 0;
  static const _replies = [
    '오늘은 창밖 구름을 구경했어! 토끼 모양 구름도 있었어.',
    '좋아! 우리 같이 숨바꼭질하자. 내가 먼저 숨을게! 열까지 세고 찾으러 와야 해.',
  ];
  @override
  Future<String?> replyTo(CharacterFriend friend, String text) async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    return _replies[_turn++ % _replies.length];
  }

  @override
  Future<List<ChatLine>> history(CharacterFriend friend) async => const [];
}

/// 실제 iPad의 화면 키보드를 띄운 채 친구와 이야기한다. 단계마다
/// `CHECKPOINT` 줄을 남겨 바깥에서 기기 화면을 캡처할 수 있게 한다.
/// 기기 데이터에 연결하지 않는 세션 전용 저장소를 쓴다.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  Future<void> frames(WidgetTester tester, int milliseconds) async {
    for (var t = 0; t < milliseconds; t += 50) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(tester.takeException(), isNull);
  }

  testWidgets('실제 iPad: 키보드를 띄운 채 말풍선으로 대화', (tester) async {
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
    final report = <String, Object?>{};
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    Rect panel() => tester.getRect(find.byKey(const ValueKey('chat')));
    void inRoom(String step) {
      final inset =
          tester.view.viewInsets.bottom / tester.view.devicePixelRatio;
      final bubble = tester.getRect(find.byType(SceneSpeech));
      final figure = tester.getRect(find.byKey(const ValueKey('house-figure')));
      final rug = tester.getRect(find.byKey(const ValueKey('house-rug')));
      report[step] = {
        'keyboard': inset,
        'bubble': [bubble.left, bubble.top, bubble.right, bubble.bottom],
        'figure': [figure.left, figure.top, figure.right, figure.bottom],
        'rug': [rug.left, rug.top, rug.right, rug.bottom],
        'panel': [panel().left, panel().top, panel().right, panel().bottom],
      };
      expect(bubble.top, greaterThanOrEqualTo(0), reason: step);
      expect(bubble.left, greaterThanOrEqualTo(0), reason: step);
      expect(bubble.right, lessThan(panel().left), reason: step);
      expect(bubble.bottom, lessThanOrEqualTo(screen.height - inset));
      expect(figure.bottom, lessThanOrEqualTo(screen.height - inset));
      expect(rug.bottom, lessThanOrEqualTo(screen.height - inset));
      expect(panel().bottom, lessThanOrEqualTo(screen.height - inset));
    }

    // 릴리스 빌드로 기기에서 직접 돌릴 때도 결과를 꺼낼 수 있게 앱의
    // 임시 폴더에 단계마다 남긴다. 저장 데이터 폴더는 건드리지 않는다.
    void save(String reached) {
      report['reached'] = reached;
      File(
        '${Directory.systemTemp.path}/house_chat_keyboard.json',
      ).writeAsStringSync(jsonEncode(report));
    }

    Future<void> checkpoint(String name, {int hold = 5000}) async {
      save(name);
      // ignore: avoid_print
      print('CHECKPOINT $name');
      await frames(tester, hold);
    }

    // 릴리스 빌드에는 접근성 트리가 없어 글자로 찾는다.
    try {
      await tester.tap(find.text('대화하기'));
      await frames(tester, 900);
      await checkpoint('chat-open');

      // 실제 화면 키보드를 띄운다.
      tester.testTextInput.unregister();
      final field = find.byKey(const ValueKey('house-chat-field'));
      await tester.tap(field);
      await frames(tester, 1500);
      expect(tester.view.viewInsets.bottom, greaterThan(0));
      await checkpoint('keyboard-up');

      await tester.tap(find.widgetWithText(ActionChip, '오늘 뭐 했어?'));
      await frames(tester, 400);
      await checkpoint('keyboard-thinking', hold: 300);
      await frames(tester, 1500);
      inRoom('keyboard-reply');
      await checkpoint('keyboard-reply');

      tester.widget<TextField>(field).controller!.text = '같이 놀자';
      await tester.pump();
      await tester.tap(find.byTooltip('보내기'));
      await frames(tester, 2200);
      inRoom('keyboard-long-reply');
      await checkpoint('keyboard-long-reply');

      FocusManager.instance.primaryFocus?.unfocus();
      await frames(tester, 1200);
      inRoom('keyboard-down');
      await checkpoint('keyboard-down');
    } catch (error) {
      report['error'] = '$error';
      save('failed');
      rethrow;
    }
    save('done');
    binding.reportData = report;
    await tester.pumpWidget(const SizedBox());
  }, timeout: const Timeout(Duration(minutes: 3)));
}
