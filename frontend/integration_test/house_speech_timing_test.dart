import 'dart:convert';
import 'dart:io';

import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/data/chat_service.dart';
import 'package:bogle_app/src/models/character_friend.dart';
import 'package:bogle_app/src/screens/friend_screen.dart';
import 'package:bogle_app/src/screens/house/scene_speech.dart';
import 'package:bogle_app/src/theme/bogle_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

class _Chat implements ChatService {
  @override
  Future<String?> replyTo(CharacterFriend friend, String text) async =>
      '오늘은 창밖 구름을 구경했어! 토끼 모양 구름도 있었어.';
  @override
  Future<List<ChatLine>> history(CharacterFriend friend) async => const [];
}

/// 실제 iPad에서 말풍선이 떠 있는 시간과 초대 인사 간격을 잰다. 결과는 앱의
/// 임시 폴더에 남긴다(릴리스 빌드로 기기에서 돌릴 때 꺼내 보기 위해).
/// 기기 데이터에 연결하지 않는 세션 전용 저장소를 쓴다.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('실제 iPad: 말풍선 유지 시간과 초대 인사 간격', (tester) async {
    final report = <String, Object?>{};
    void save(String reached) {
      report['reached'] = reached;
      File(
        '${Directory.systemTemp.path}/house_speech_timing.json',
      ).writeAsStringSync(jsonEncode(report));
    }

    final repo = InMemoryCharacterRepository();
    final friends = await repo.fetchFriends();
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
    final clock = Stopwatch()..start();
    // 말풍선이 바뀌는 동안에는 이전 것과 새 것이 함께 있다: 새 것이 마지막이다.
    SceneSpeech? speech() =>
        tester.widgetList<SceneSpeech>(find.byType(SceneSpeech)).lastOrNull;

    /// Pumps till [done], returning the milliseconds it took (or -1).
    Future<int> until(bool Function() done, {int limit = 20000}) async {
      final start = clock.elapsedMilliseconds;
      while (clock.elapsedMilliseconds - start < limit) {
        if (done()) return clock.elapsedMilliseconds - start;
        await tester.pump(const Duration(milliseconds: 50));
      }
      return -1;
    }

    try {
      await until(() => speech() != null);
      final greeting = speech()!.text;
      report['greetingShownMs'] = await until(() => speech() == null);
      report['greetingHoldMs'] = speechHold(greeting).inMilliseconds;
      save('greeting-faded');

      // 릴리스 빌드에는 접근성 트리가 없어 글자로 찾는다.
      await tester.tap(find.text('초대하기').first);
      await until(() => find.text('뚜치').evaluate().isNotEmpty, limit: 3000);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('뚜치').last);
      await until(() => speech()?.speaker == '뭉글이', limit: 15000);
      final welcome = speech()!.text;
      report['hostToGuestMs'] = await until(
        () => speech()?.speaker == '뚜치',
        limit: 15000,
      );
      report['expectedReplyDelayMs'] = greetingReplyDelay(
        welcome,
      ).inMilliseconds;
      save('guest-answered');
      report['guestShownMs'] = await until(() => speech() == null);
      save('guest-faded');

      await tester.tap(find.text('대화하기').first);
      await tester.pump(const Duration(milliseconds: 900));
      await tester.tap(find.widgetWithText(ActionChip, '오늘 뭐 했어?'));
      await until(() => speech()?.text.contains('구름') ?? false);
      final heldFrom = clock.elapsedMilliseconds;
      await until(() => speech() == null, limit: 15000);
      report['chatHeldMs'] = clock.elapsedMilliseconds - heldFrom;
      report['chatStillShowing'] = speech() != null;
      save('done');
    } catch (error) {
      report['error'] = '$error';
      save('failed');
      rethrow;
    }
    binding.reportData = report;
    await tester.pumpWidget(const SizedBox());
  }, timeout: const Timeout(Duration(minutes: 3)));
}
