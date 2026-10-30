import 'package:bogle_app/src/data/api/api_client.dart';
import 'package:bogle_app/src/data/character_generation.dart';
import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/data/chat_service.dart';
import 'package:bogle_app/src/models/character_friend.dart';
import 'package:bogle_app/src/screens/archive_screen.dart';
import 'package:bogle_app/src/screens/friend_screen.dart';
import 'package:bogle_app/src/screens/house/house_widgets.dart';
import 'package:bogle_app/src/screens/setup_friend_screen.dart';
import 'package:bogle_app/src/theme/bogle_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _offline = ApiException(
  statusCode: 0,
  code: 'offline',
  message: '인터넷 연결을 확인하고 다시 시도해 주세요.',
  retryable: true,
);

/// Fails the first [failures] times, then works.
class FlakyFriends extends InMemoryCharacterRepository {
  FlakyFriends({this.fetchFailures = 0, this.createFailures = 0});
  int fetchFailures;
  int createFailures;

  @override
  Future<List<CharacterFriend>> fetchFriends() {
    if (fetchFailures > 0) {
      fetchFailures--;
      return Future.error(_offline);
    }
    return super.fetchFriends();
  }

  @override
  Future<CharacterFriend> createFriend(NewFriend friend) {
    if (createFailures > 0) {
      createFailures--;
      return Future.error(_offline);
    }
    return super.createFriend(friend);
  }
}

class RememberingChat implements ChatService {
  RememberingChat(this.past);
  final List<ChatLine> past;
  @override
  Future<List<ChatLine>> history(CharacterFriend friend) async => past;
  @override
  Future<String?> replyTo(CharacterFriend friend, String text) async => null;
}

Future<void> show(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(1366, 1024);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildBogleTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: home,
    ),
  );
  await tester.pumpAndSettle();
}

class _NoVoice implements VoiceInput {
  @override
  Future<bool> start(ValueChanged<String> onWords, VoidCallback onDone) async =>
      false;
  @override
  Future<void> stop() async {}
}

void main() {
  setUpAll(() async {
    for (final f in await InMemoryCharacterRepository().fetchFriends()) {
      await anchorsFor(f.assetPath);
    }
  });

  testWidgets('an archive that cannot load says so and loads on retry', (
    tester,
  ) async {
    final friends = FlakyFriends(fetchFailures: 1);

    await show(tester, ArchiveScreen(repository: friends));

    expect(find.text('친구들을 불러오지 못했어요'), findsOneWidget);
    expect(find.text('인터넷 연결을 확인하고 다시 시도해 주세요.'), findsOneWidget);
    await tester.tap(find.text('다시 불러오기'));
    await tester.pumpAndSettle();
    expect(find.text('친구들을 불러오지 못했어요'), findsNothing);
    expect(find.text('뭉글이'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a friend that cannot be saved keeps every answer for another '
      'try', (tester) async {
    final friends = FlakyFriends(createFailures: 1);
    await show(
      tester,
      SetupFriendScreen(
        art: const GeneratedArt(assetPath: 'assets/figma/character_friend.svg'),
        repository: friends,
        voice: _NoVoice(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();

    Future<void> type(String answer) async {
      if (find.text('글자로 적기').evaluate().isNotEmpty) {
        await tester.tap(find.text('글자로 적기'));
        await tester.pumpAndSettle();
      }
      await tester.enterText(
        find.byKey(const ValueKey('setup-answer')),
        answer,
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, '다음'));
      await tester.pumpAndSettle();
    }

    await type('구름이');
    // The rest is chosen, each followed by 다음.
    await tester.tap(find.text('엉뚱한 상상가'));
    await tester.pump();
    await tester.tap(find.text('다음'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('구름 구경하기'));
    await tester.pump();
    await tester.tap(find.text('다음'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('speech-manner-plain')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('이 말투로 정하기'));
    await tester.pumpAndSettle();
    expect(find.textContaining('인터넷 연결을 확인하고'), findsOneWidget);
    expect(find.text('친구가 되었어요!'), findsNothing);
    expect(find.text('이 말투로 정하기'), findsOneWidget); // still here

    await tester.tap(find.text('이 말투로 정하기'));
    await tester.pumpAndSettle();
    expect(find.text('친구가 되었어요!'), findsOneWidget);
    expect((await friends.fetchFriends()).last.name, '구름이');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the chat from earlier visits is there when the house opens', (
    tester,
  ) async {
    final friends = InMemoryCharacterRepository();
    final friend = (await friends.fetchFriends()).first;
    await show(
      tester,
      FriendScreen(
        repository: friends,
        friend: friend.copyWith(
          sleep: const SleepSchedule(bedtime: 0, wakeTime: 0),
        ),
        chat: RememberingChat(const [
          (mine: true, text: '어제 뭐 했어?'),
          (mine: false, text: '구름 구경했지요!'),
        ]),
      ),
    );

    await tester.tap(find.bySemanticsLabel('대화하기'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('이전 이야기'));
    await tester.pumpAndSettle();
    expect(chatLine('어제 뭐 했어?'), findsOneWidget);
    expect(chatLine('구름 구경했지요!'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

/// A chat balloon's text: they keep words whole with word joiners.
Finder chatLine(String text) => find.byWidgetPredicate(
  (w) => w is Text && w.data?.replaceAll('\u2060', '') == text,
);
