import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/data/starter_friends.dart';
import 'package:bogle_app/src/screens/archive_screen.dart';
import 'package:bogle_app/src/theme/bogle_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> open(WidgetTester tester, CharacterRepository friends) async {
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
      home: ArchiveScreen(repository: friends),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('archive has no favourites and keeps repository order', (
    tester,
  ) async {
    await open(tester, InMemoryCharacterRepository());
    expect(find.text('뭉글이의 집에 놀러 가기'), findsOneWidget);
    expect(find.byIcon(Icons.favorite_rounded), findsNothing);
    expect(find.byIcon(Icons.favorite_border_rounded), findsNothing);
    expect(find.byTooltip('뭉글이 즐겨찾기'), findsNothing);
    expect(find.byTooltip('뭉글이 즐겨찾기 빼기'), findsNothing);
    await tester.drag(
      find.byKey(const ValueKey('archive-carousel')),
      const Offset(-420, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('뚜치의 집에 놀러 가기'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('edit mode renames a friend and says goodbye with undo', (
    tester,
  ) async {
    final friends = InMemoryCharacterRepository();
    await open(tester, friends);

    expect(find.text('편집'), findsNothing);
    expect(find.text('새 친구 만들기'), findsNothing);

    // Rename the friend in the middle.
    await tester.tap(find.byTooltip('뭉글이 편집'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('edit-name')), '몽글이');
    await tester.enterText(
      find.byKey(const ValueKey('edit-introduction')),
      '바닷속을 여행하는 작은 해파리야.',
    );
    await tester.tap(find.byKey(const ValueKey('speech-manner-plain')));
    await tester.tap(find.text('편한 말'));
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    final renamed = (await friends.fetchFriends()).firstWhere(
      (f) => f.id == 'mungle',
    );
    expect(renamed.name, '몽글이');
    expect(renamed.introduction, '바닷속을 여행하는 작은 해파리야.');
    expect(renamed.personality, '활발하고 호기심이 많아요');
    expect(renamed.toJson()['introduction'], renamed.introduction);
    expect(renamed.speechStyle, 'plain_casual');

    // Saying goodbye asks first; "그대로 두기" keeps the friend.
    await tester.tap(find.byTooltip('몽글이 삭제'));
    await tester.pumpAndSettle();
    expect(find.text('몽글이와 작별할까요?'), findsOneWidget);
    await tester.tap(find.text('그대로 두기'));
    await tester.pumpAndSettle();
    expect(await friends.fetchFriends(), hasLength(starterFriends().length));

    await tester.tap(find.byTooltip('몽글이 삭제'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '작별하기').last);
    await tester.pumpAndSettle();
    expect(
      await friends.fetchFriends(),
      hasLength(starterFriends().length - 1),
    );
    expect(find.text('몽글이와 작별했어요'), findsOneWidget);
    // The carousel lands on the next friend, not on an empty slot.
    expect(find.text('뚜치의 집에 놀러 가기'), findsOneWidget);

    await tester.tap(find.text('다시 데려오기'));
    await tester.pumpAndSettle();
    expect(await friends.fetchFriends(), hasLength(starterFriends().length));
    expect(find.text('몽글이의 집에 놀러 가기'), findsOneWidget);
  });

  testWidgets('saying goodbye to every friend leaves the empty archive', (
    tester,
  ) async {
    final friends = InMemoryCharacterRepository();
    await open(tester, friends);
    for (var i = 0; i < starterFriends().length; i++) {
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('archive-selected-card')),
          matching: find.byKey(const ValueKey('archive-card-delete')),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '작별하기').last);
      await tester.pumpAndSettle();
    }
    expect(await friends.fetchFriends(), isEmpty);
    expect(find.text('아직 집에 사는 친구가 없어요'), findsOneWidget);
    expect(find.text('편집'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cards show no level or memories; corners carry the design '
      'icons', (tester) async {
    await open(tester, InMemoryCharacterRepository());
    final card = find.byKey(const ValueKey('archive-selected-card'));
    expect(
      find.descendant(of: card, matching: find.textContaining('Lv.')),
      findsNothing,
    );
    expect(
      find.descendant(of: card, matching: find.textContaining('추억')),
      findsNothing,
    );
    final delete = tester.getRect(
      find.descendant(
        of: card,
        matching: find.byKey(const ValueKey('archive-card-delete')),
      ),
    );
    final edit = tester.getRect(
      find.descendant(
        of: card,
        matching: find.byKey(const ValueKey('archive-card-edit')),
      ),
    );
    final box = tester.getRect(card);
    // Trash bottom left, brush bottom right, as in Figma 243:1612.
    expect(delete.center.dx, lessThan(box.left + box.width * .25));
    expect(edit.center.dx, greaterThan(box.right - box.width * .25));
    expect(delete.bottom, greaterThan(box.bottom - 80));
    expect(edit.bottom, greaterThan(box.bottom - 80));
  });
}
