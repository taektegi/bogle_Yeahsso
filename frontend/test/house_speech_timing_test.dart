import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/screens/friend_screen.dart';
import 'package:bogle_app/src/screens/house/house_widgets.dart';
import 'package:bogle_app/src/screens/house/scene_speech.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'house_test.dart' show afternoon, firstFriend, show;

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final friend in await InMemoryCharacterRepository().fetchFriends()) {
      await anchorsFor(friend.assetPath);
    }
  });

  Future<void> open(WidgetTester tester) async {
    final repo = InMemoryCharacterRepository();
    await show(
      tester,
      FriendScreen(
        repository: repo,
        friend: await firstFriend(repo),
        clock: afternoon,
      ),
    );
  }

  Finder speech() => find.byType(SceneSpeech);

  testWidgets('집 화면의 말풍선은 읽을 만큼 떠 있다가 사라진다', (tester) async {
    await open(tester);
    expect(speech(), findsOneWidget);
    final line = tester.widget<SceneSpeech>(speech()).text;
    final hold = speechHold(speechPages(line).first);
    await tester.pump(hold - const Duration(milliseconds: 500));
    expect(speech(), findsOneWidget, reason: '아직 읽는 중');
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(speech(), findsNothing);
    // 다시 쓰다듬으면 새 말풍선이 뜬다.
    await tester.tap(find.byKey(const ValueKey('house-figure')));
    await tester.pumpAndSettle();
    expect(speech(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('대화 중에는 말풍선이 유지되고, 대화를 닫으면 잠시 뒤 사라진다', (tester) async {
    await open(tester);
    await tester.tap(find.bySemanticsLabel('대화하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ActionChip, '오늘 뭐 했어?'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    final reply = tester.widget<SceneSpeech>(speech()).text;
    expect(tester.widget<SceneSpeech>(speech()).holds, isTrue);
    for (var t = 0; t < 20; t++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(speech(), findsOneWidget, reason: '읽을 때까지 유지');
    expect(tester.widget<SceneSpeech>(speech()).text, reply);

    await tester.tap(find.byKey(const ValueKey('house-chat-return')));
    await tester.pumpAndSettle();
    expect(speech(), findsOneWidget, reason: '닫자마자 사라지지 않는다');
    await tester.pump(const Duration(seconds: 9));
    await tester.pumpAndSettle();
    expect(speech(), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
