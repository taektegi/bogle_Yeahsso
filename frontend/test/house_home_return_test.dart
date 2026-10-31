import 'package:bogle_app/src/widgets/bogle_widgets.dart';
import 'package:flutter/gestures.dart';
import 'package:bogle_app/src/widgets/house_transition.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _archiveKey = ValueKey('test-archive');
const _houseKey = ValueKey('test-house');
const _art = 'assets/figma/archive_nemorin.png';

Widget _friend(bool standing) => SizedBox(
  width: standing ? 260 : 140,
  height: standing ? 260 : 140,
  child: friendHero(
    id: 'test-friend',
    assetPath: _art,
    standing: standing,
    child: const ColoredBox(color: Colors.blue),
  ),
);

Future<void> _openHouse(
  WidgetTester tester, {
  bool reduceMotion = false,
  bool extraPage = false,
}) async {
  tester.view.physicalSize = const Size(1194, 834);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final nav = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: nav,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: child!,
      ),
      home: const Scaffold(body: Text('original-home')),
    ),
  );
  if (extraPage) {
    nav.currentState!.push(bogleRoute(const Scaffold(body: Text('extra'))));
    await tester.pumpAndSettle();
  }
  nav.currentState!.push(
    bogleRoute(
      Scaffold(
        key: _archiveKey,
        body: Center(child: _friend(false)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  nav.currentState!.push(
    houseRoute(
      Scaffold(
        key: _houseKey,
        body: Builder(
          builder: (context) => Column(
            children: [
              // The house's top bar has tooltips: overlay portals that must
              // survive the switch to the Home closing.
              Tooltip(
                message: 'home',
                child: TextButton(
                  onPressed: () => goHome(context),
                  child: const Text('home'),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('back'),
              ),
              _friend(true),
            ],
          ),
        ),
      ),
      from: const Rect.fromLTWH(500, 300, 180, 220),
      color: Colors.blue,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Home folds like Back, then shrinks beyond the card to nothing', (
    tester,
  ) async {
    await _openHouse(tester, extraPage: true);
    final homeAction = tester
        .widget<TextButton>(find.widgetWithText(TextButton, 'home'))
        .onPressed!;
    await tester.tap(find.text('home'));
    await tester.pump();
    expect(find.byKey(_archiveKey, skipOffstage: false), findsNothing);
    expect(find.text('extra', skipOffstage: false), findsNothing);
    expect(find.byKey(const ValueKey('friend-in-flight')), findsNothing);
    final collapse = find.byKey(const ValueKey('house-home-collapse'));
    final panel = find.byKey(const ValueKey('house-home-panel'));
    expect(collapse, findsOneWidget);
    expect(tester.getSize(panel), const Size(1194, 834));
    final friend = find.descendant(
      of: find.byKey(const ValueKey('house-home-friend')),
      matching: find.byType(FriendArtwork),
    );
    final fullFriendWidth =
        tester.getBottomRight(friend).dx - tester.getTopLeft(friend).dx;
    await tester.pump(const Duration(milliseconds: 180));
    // The opening stage matches Back: the coloured panel still fills the
    // screen while the circular window closes and the friend moves out.
    expect(tester.getSize(panel), const Size(1194, 834));
    expect(
      tester.getBottomRight(friend).dx - tester.getTopLeft(friend).dx,
      lessThan(fullFriendWidth),
    );
    expect(find.text('original-home'), findsOneWidget);
    // A repeated Home action must not pop the home screen.
    homeAction();
    await tester.pump(const Duration(milliseconds: 650));
    // Near the end neither the panel nor the friend stops at card size.
    expect(tester.getSize(panel).width, lessThan(18));
    expect(tester.getSize(panel).height, lessThan(22));
    expect(
      tester.getBottomRight(friend).dx - tester.getTopLeft(friend).dx,
      lessThan(5),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    expect(find.byKey(_houseKey), findsNothing);
    expect(find.text('original-home'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final reduceMotion in [false, true]) {
    testWidgets('nested studio Home reveals only the existing home '
        '(reduced motion: $reduceMotion)', (tester) async {
      await _openHouse(tester, extraPage: true, reduceMotion: reduceMotion);
      final nav = tester.state<NavigatorState>(find.byType(Navigator));
      nav.push(bogleRoute(const Scaffold(body: Text('nested-profile'))));
      await tester.pumpAndSettle();
      nav.push(
        bogleRoute(
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => goHome(context),
                child: const Text('studio-home'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final returnHome = tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'studio-home'))
          .onPressed!;
      await tester.tap(find.text('studio-home'));
      await tester.pump();
      // Check during the transition, not just after every animation ends:
      // the house used to keep closing underneath the studio for 800 ms.
      for (final elapsed in [0, 100, 140, 300]) {
        await tester.pump(Duration(milliseconds: elapsed));
        expect(find.byKey(_houseKey, skipOffstage: false), findsNothing);
        expect(find.byKey(_archiveKey, skipOffstage: false), findsNothing);
        expect(find.text('nested-profile', skipOffstage: false), findsNothing);
        expect(find.text('extra', skipOffstage: false), findsNothing);
        expect(find.byKey(const ValueKey('house-home-collapse')), findsNothing);
        expect(tester.takeException(), isNull);
      }
      // A delayed or repeated tap must leave the original root alone.
      returnHome();
      await tester.pumpAndSettle();
      expect(find.text('original-home'), findsOneWidget);
      expect(nav.canPop(), isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Back keeps the archive card flight and its original duration', (
    tester,
  ) async {
    await _openHouse(tester);
    await tester.tap(find.text('back'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('friend-in-flight')), findsOneWidget);
    expect(find.byKey(const ValueKey('house-home-collapse')), findsNothing);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(_houseKey), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byKey(_houseKey), findsNothing);
    expect(find.byKey(_archiveKey), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Home respects reduced motion and still clears intermediate pages',
    (tester) async {
      await _openHouse(tester, reduceMotion: true);
      await tester.tap(find.text('home'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('house-home-collapse')), findsNothing);
      expect(find.byKey(_archiveKey, skipOffstage: false), findsNothing);
      expect(find.text('original-home'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Home with a tooltip showing (a pointer resting on the button) '
      'closes cleanly', (tester) async {
    await _openHouse(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('home')));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('home'), findsNWidgets(2), reason: 'tooltip is up');
    await mouse.down(tester.getCenter(find.text('home').first));
    await mouse.up();
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(find.text('original-home'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
