import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/data/friend_talk.dart';
import 'package:bogle_app/src/models/friend_status.dart';
import 'package:bogle_app/src/screens/friend_screen.dart';
import 'package:bogle_app/src/screens/house/scene_speech.dart';
import 'package:bogle_app/src/theme/bogle_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  Future<void> frames(WidgetTester tester, int ms) async {
    for (var i = 0; i < ms; i += 50) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(tester.takeException(), isNull);
  }

  testWidgets('iPad: 초대 카펫 확장·복귀와 한국어 대사·간식 기록', (tester) async {
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
        theme: buildBogleTheme(),
        home: FriendScreen(
          repository: repo,
          friend: friends.first,
          clock: () => DateTime(2026, 10, 30, 14),
        ),
      ),
    );
    await frames(tester, 1600);
    final rug = find.byKey(const ValueKey('house-rug'));
    final alone = tester.getRect(rug);
    await binding.takeScreenshot('rug-alone');
    await tester.tap(find.bySemanticsLabel('초대하기'));
    await frames(tester, 450);
    await tester.tap(find.bySemanticsLabel('네모린 초대하기'));
    await frames(tester, 200);
    final during = tester.getRect(rug);
    expect(during.top, closeTo(alone.top, .2));
    await binding.takeScreenshot('rug-expanding');
    await frames(tester, 4200);
    final expanded = tester.getRect(rug);
    expect(expanded.width, greaterThan(alone.width));
    expect(expanded.top, closeTo(alone.top, .2));
    final greeting = tester.widget<SceneSpeech>(find.byType(SceneSpeech));
    expect(greeting.speaker, '네모린');
    expect(greeting.text, matches(RegExp('초대|놀러')));
    await binding.takeScreenshot('rug-expanded');
    await tester.tap(find.bySemanticsLabel('간식주기'));
    await frames(tester, 450);
    await tester.tap(find.bySemanticsLabel(RegExp('^사과 주기')));
    await frames(tester, 4500);
    expect(await repo.fetchMemories('mungle'), contains('네모린과 사과를 나눠 먹었어.'));
    await binding.takeScreenshot('natural-snack-dialogue');
    await tester.tap(find.bySemanticsLabel('배웅하기'));
    await frames(tester, 8200);
    final restored = tester.getRect(rug);
    expect(restored.width, closeTo(alone.width, .2));
    expect(find.byKey(const ValueKey('house-guest')), findsNothing);
    await binding.takeScreenshot('rug-restored');
    final talk = FriendTalk(friends.first.copyWith(speechStyle: '다정한 반말'));
    expect(talk.register, Register.casual);
    final polite = FriendTalk(friends.first.copyWith(speechStyle: '해요체'));
    for (var i = 0; i < 20; i++) {
      final text = polite.say(TalkTopic.treat, thing: '밤');
      expect(text, isNot(contains('밤예요')));
    }
    binding.reportData = {
      ...?binding.reportData,
      'rugAloneWidth': alone.width,
      'rugExpandedWidth': expanded.width,
      'rugRestoredWidth': restored.width,
      'rugTopAnchored': true,
      'sharedMemory': '네모린과 사과를 나눠 먹었어.',
      'registerAndBatchimChecked': true,
    };
    await tester.pumpWidget(const SizedBox());
  });
}
