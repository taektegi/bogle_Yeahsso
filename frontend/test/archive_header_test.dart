import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/screens/archive_screen.dart';
import 'package:bogle_app/src/theme/bogle_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/top_bar_expect.dart';

void main() {
  for (final size in const [
    Size(1024, 768),
    Size(1194, 834),
    Size(1366, 1024),
  ]) {
    for (final empty in [false, true]) {
      testWidgets('archive keeps the shared top bar at $size, empty: $empty', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final repository = InMemoryCharacterRepository();
        if (empty) {
          for (final friend in await repository.fetchFriends()) {
            await repository.deleteFriend(friend.id);
          }
        }
        await tester.pumpWidget(
          MaterialApp(
            theme: buildBogleTheme(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            ),
            home: ArchiveScreen(repository: repository),
          ),
        );
        await tester.pumpAndSettle();

        void checkHeader() {
          // Figma 285:3691: the shared top bar with "Friends" in its pill.
          expectTopBar(tester, pill: 'Friends');
          expect(find.byKey(const ValueKey('archive-actions')), findsNothing);
          expect(find.text('새 친구 만들기'), findsNothing);
          expect(find.text('편집'), findsNothing);
          if (!empty) {
            final selected = find.byKey(
              const ValueKey('archive-selected-card'),
            );
            final card = tester.getRect(selected);
            final delete = tester.getRect(
              find.descendant(of: selected, matching: find.byTooltip('뭉글이 삭제')),
            );
            final edit = tester.getRect(
              find.descendant(of: selected, matching: find.byTooltip('뭉글이 편집')),
            );
            expect(delete.center.dy, closeTo(edit.center.dy, .1));
            expect(delete.center.dx, lessThan(card.center.dx));
            expect(edit.center.dx, greaterThan(card.center.dx));
            expect(delete.top, greaterThan(card.top + card.height * .7));
            expect(edit.bottom, lessThan(card.bottom));
            expect(find.text('난 바다에 사는 해파리야.\n심해 모험을 좋아해.'), findsWidgets);
          }
          expect(tester.takeException(), isNull);
        }

        checkHeader();
      });
    }
  }
}
