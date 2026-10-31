import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/screens/friend_screen.dart';
import 'package:bogle_app/src/screens/house/chat_panel.dart';
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

  testWidgets('대화창의 닫기 버튼은 키보드 포커스를 해제하고 대화 기록은 유지한다', (tester) async {
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
    final close = find.byKey(const ValueKey('house-chat-return'));
    expect(find.byTooltip('대화 닫기'), findsOneWidget);
    expect(tester.getSize(close).height, greaterThanOrEqualTo(52));
    expect(tester.getSize(close).width, greaterThanOrEqualTo(52));
    // 대화 중에는 간식주기·초대하기·대화하기 타일을 숨긴다.
    for (final tile in ['대화하기', '간식주기', '초대하기']) {
      expect(find.text(tile), findsNothing, reason: tile);
    }
    await tester.tap(find.widgetWithText(ActionChip, '사랑해!'));
    await tester.pump(const Duration(seconds: 1));
    Finder said(String text) => find.descendant(
      of: find.byType(ChatPanel),
      matching: find.byWidgetPredicate(
        (w) => w is Text && w.semanticsLabel == text,
      ),
    );
    // 보낸 말과 답이 따로 열지 않아도 대화창에 바로 쌓인다.
    expect(said('사랑해!'), findsOneWidget);
    final field = find.byKey(const ValueKey('house-chat-field'));
    await tester.tap(field);
    await tester.pump();
    final focus = tester.widget<TextField>(field).focusNode!;
    expect(focus.hasFocus, true);
    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat')), findsNothing);
    expect(find.byType(FriendScreen), findsOneWidget);
    expect(find.byType(EditableText), findsNothing);
    for (final tile in ['대화하기', '간식주기', '초대하기']) {
      expect(find.text(tile), findsOneWidget, reason: tile);
    }
    await tester.tap(find.bySemanticsLabel('대화하기'));
    await tester.pumpAndSettle();
    expect(said('사랑해!'), findsOneWidget);
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

  testWidgets('작은 폭과 큰 글자에서도 생각 중·수면 중에 닫을 수 있다', (tester) async {
    var closed = 0;
    final friend = await firstFriend(InMemoryCharacterRepository());
    await tester.pumpWidget(
      MaterialApp(
        theme: buildBogleTheme(),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                height: 520,
                child: ChatPanel(
                  friend: friend,
                  lines: const [(mine: false, text: '쿨쿨')],
                  enabled: false,
                  thinking: true,
                  onSend: (_, _) {},
                  onClose: () => closed++,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final close = find.byKey(const ValueKey('house-chat-return'));
    expect(tester.getSize(close).height, greaterThanOrEqualTo(52));
    await tester.tap(close);
    expect(closed, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
