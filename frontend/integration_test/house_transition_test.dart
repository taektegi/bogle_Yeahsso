import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/models/character_friend.dart';
import 'package:bogle_app/src/screens/archive_screen.dart';
import 'package:bogle_app/src/screens/friend_screen.dart';
import 'package:bogle_app/src/screens/home_screen.dart';
import 'package:bogle_app/src/screens/house/house_widgets.dart';
import 'package:bogle_app/src/theme/bogle_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('archive flight hands off smoothly for every bundled friend', (
    tester,
  ) async {
    final repository = InMemoryCharacterRepository();
    for (final friend in await repository.fetchFriends()) {
      await repository.saveFriend(
        friend.copyWith(sleep: const SleepSchedule(bedtime: 0, wakeTime: 0)),
      );
    }
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildBogleTheme(),
        home: HomeScreen(repository: repository),
      ),
    );
    // Let the display's vsync drive frames; don't force a 60 Hz pump loop.
    Future<void> wait(int milliseconds) async {
      await tester.runAsync(
        () => Future<void>.delayed(Duration(milliseconds: milliseconds)),
      );
      await tester.pump();
    }

    await wait(1000);
    await tester.tap(find.text('친구들 보러가기'));
    await wait(800);
    for (final name in ['뭉글이', '뚜치', '네모린', '뭉글이']) {
      final visit = find.text('$name의 집에 놀러 가기');
      if (visit.evaluate().isEmpty) {
        await tester.tap(find.bySemanticsLabel(RegExp('^$name,')));
        await wait(750);
      }
      await tester.tap(visit);
      await wait(160);
      // In a first visit the rig may still be loading. A Hero locks this
      // footprint during flight; it must not grow when the placeholder ends.
      final inFlightSize = tester.getSize(
        find.byType(FriendFigure, skipOffstage: false),
      );
      await wait(1400);
      expect(find.byType(FriendScreen), findsOneWidget);
      expect(find.byType(FriendFigure), findsOneWidget);
      final landedSize = tester.getSize(find.byType(FriendFigure));
      expect(landedSize.width, closeTo(inFlightSize.width, .1), reason: name);
      expect(landedSize.height, closeTo(inFlightSize.height, .1), reason: name);
      expect(find.byKey(const ValueKey('friend-in-flight')), findsNothing);
      expect(tester.takeException(), isNull);
      await binding.takeScreenshot('house-transition-$name');
      await tester.tap(find.byKey(const ValueKey('house-back')));
      await wait(1100);
      expect(find.byType(FriendScreen), findsNothing);
      expect(
        find.byKey(const ValueKey('archive-selected-card')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
    await tester.tap(find.text('뭉글이의 집에 놀러 가기'));
    await wait(1500);
    await binding.takeScreenshot('house-home-before');
    await tester.tap(find.byKey(const ValueKey('top-action-홈')));
    await wait(180);
    expect(find.byType(ArchiveScreen, skipOffstage: false), findsNothing);
    expect(find.byKey(const ValueKey('friend-in-flight')), findsNothing);
    expect(find.byKey(const ValueKey('house-home-collapse')), findsOneWidget);
    expect(find.byKey(const ValueKey('house-home-friend')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await binding.takeScreenshot('house-home-during');
    await wait(480);
    await binding.takeScreenshot('house-home-ending');
    await wait(800);
    expect(find.byType(FriendScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    await binding.takeScreenshot('house-home-after');
    await tester.pumpWidget(const SizedBox());
  });
}
