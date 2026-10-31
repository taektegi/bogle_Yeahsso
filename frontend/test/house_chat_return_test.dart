import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/screens/friend_screen.dart';
import 'package:bogle_app/src/screens/house/chat_panel.dart';
import 'package:bogle_app/src/screens/house/conversation_dock.dart';
import 'package:bogle_app/src/screens/house/house_widgets.dart';
import 'package:bogle_app/src/theme/bogle_theme.dart';
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

  testWidgets('명시적인 집 복귀 버튼은 키보드 포커스를 해제하고 대화 기록은 유지한다', (tester) async {
    final repo = InMemoryCharacterRepository();
    await show(
      tester,
      FriendScreen(
        repository: repo,
        friend: await firstFriend(repo),
        clock: afternoon,
      ),
      size: const Size(1024, 768),
    );
    await tester.tap(find.bySemanticsLabel('대화하기'));
    await tester.pumpAndSettle();
    final back = find.byKey(const ValueKey('house-chat-return'));
    expect(find.text('집으로 돌아가기'), findsOneWidget);
    expect(tester.getSize(back).height, greaterThanOrEqualTo(52));
    await tester.tap(find.widgetWithText(ActionChip, '사랑해!'));
    await tester.pump(const Duration(seconds: 1));
    final field = find.byKey(const ValueKey('house-chat-field'));
    await tester.tap(field);
    await tester.pump();
    final focus = tester.widget<TextField>(field).focusNode!;
    expect(focus.hasFocus, true);
    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat')), findsNothing);
    expect(find.byType(FriendScreen), findsOneWidget);
    expect(find.byType(EditableText), findsNothing);
    await tester.tap(find.bySemanticsLabel('대화하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('이전 이야기'));
    await tester.pumpAndSettle();
    expect(find.byType(ChatPanel), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ChatPanel),
        matching: find.byWidgetPredicate(
          (w) => w is Text && w.semanticsLabel == '사랑해!',
        ),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('house-history-return')));
    await tester.pumpAndSettle();
    expect(find.byType(ChatPanel), findsNothing);
    expect(back, findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('시스템 뒤로 가기는 대화부터 닫고 캐릭터 집을 유지한다', (tester) async {
    final repo = InMemoryCharacterRepository();
    final friend = await firstFriend(repo);
    await show(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: FilledButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => FriendScreen(
                  repository: repo,
                  friend: friend,
                  clock: afternoon,
                ),
              ),
            ),
            child: const Text('집 열기'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('집 열기'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('대화하기'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(FriendScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('chat')), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(FriendScreen), findsNothing);
    expect(find.text('집 열기'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('작은 폭과 큰 글자에서도 생각 중·수면 중에 돌아갈 수 있다', (tester) async {
    var closed = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildBogleTheme(),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: ConversationDock(
                  enabled: false,
                  thinking: true,
                  onSend: (_, _) {},
                  onClose: () => closed++,
                  onHistory: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final back = find.byKey(const ValueKey('house-chat-return'));
    expect(tester.getSize(back).height, greaterThanOrEqualTo(52));
    await tester.tap(back);
    expect(closed, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
