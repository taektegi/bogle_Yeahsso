import 'package:bogle_app/src/data/character_generation.dart';
import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/screens/archive_screen.dart';
import 'package:bogle_app/src/screens/create_studio_screen.dart';
import 'package:bogle_app/src/screens/home_screen.dart';
import 'package:bogle_app/src/screens/profile_screen.dart';
import 'package:bogle_app/src/screens/setup_friend_screen.dart';
import 'package:bogle_app/src/data/profile_repository.dart';
import 'package:bogle_app/src/theme/bogle_theme.dart';
import 'package:bogle_app/src/widgets/top_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/top_bar_expect.dart';

Future<void> _show(WidgetTester tester, Size size, Widget page) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildBogleTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: true,
          // An iPad's status bar and home indicator.
          padding: const EdgeInsets.only(top: 24, bottom: 20),
        ),
        child: child!,
      ),
      home: page,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Bogle logo returns to the existing home through nested pages', (
    tester,
  ) async {
    final repo = InMemoryCharacterRepository();
    await _show(tester, const Size(1194, 834), HomeScreen(repository: repo));
    final homeState = tester.state(find.byType(HomeScreen));
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));

    // Already on home: no duplicate route or replay of the entrance.
    await tester.tap(find.byKey(const ValueKey('bogle-home-button')));
    await tester.pumpAndSettle();
    expect(navigator.canPop(), isFalse);
    expect(tester.state(find.byType(HomeScreen)), same(homeState));

    navigator.push<void>(
      MaterialPageRoute(builder: (_) => ArchiveScreen(repository: repo)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('top-action-마이페이지')));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileScreen), findsOneWidget);

    final logo = find.byKey(const ValueKey('bogle-home-button'));
    expect(tester.getSize(logo).height, greaterThanOrEqualTo(48));
    expect(tester.getSize(logo).width, greaterThanOrEqualTo(48));
    final semantics = tester.ensureSemantics();
    expect(
      tester.getSemantics(find.byType(BogleLogo)),
      matchesSemantics(label: '보글 홈', isButton: true, hasTapAction: true),
    );
    semantics.dispose();

    await tester.tap(logo);
    await tester.pumpAndSettle();
    expect(find.byType(ArchiveScreen), findsNothing);
    expect(find.byType(ProfileScreen), findsNothing);
    expect(navigator.canPop(), isFalse);
    expect(tester.state(find.byType(HomeScreen)), same(homeState));
    expect(tester.takeException(), isNull);
  });

  for (final size in const [
    Size(1024, 768),
    Size(1194, 834),
    Size(1366, 1024),
  ]) {
    testWidgets('every page puts the top bar where home has it at $size', (
      tester,
    ) async {
      final repo = InMemoryCharacterRepository();
      await _show(tester, size, HomeScreen(repository: repo));
      expectTopBar(tester, pill: 'Welcome!', logoKey: 'home-brand');
      final logo = tester.getRect(find.byKey(const ValueKey('home-brand')));
      final icons = tester.getRect(find.byKey(const ValueKey('top-bar-icons')));

      for (final (page, pill) in [
        (ArchiveScreen(repository: repo), 'Friends'),
        (
          SetupFriendScreen(
            art: const GeneratedArt(
              assetPath: 'assets/figma/character_friend.svg',
            ),
            repository: repo,
          ),
          'Setting',
        ),
        (CreateStudioScreen(repository: repo), null),
        (
          ProfileScreen(
            repository: repo,
            profileRepository: InMemoryProfileRepository(),
          ),
          '그린고블린',
        ),
      ]) {
        await _show(tester, size, page);
        expectTopBar(tester, pill: pill);
        final here = tester.getRect(find.byKey(const ValueKey('top-bar-logo')));
        expect(here.topLeft, offsetMoreOrLessEquals(logo.topLeft, epsilon: .5));
        expect(
          tester.getRect(find.byKey(const ValueKey('top-bar-icons'))).topLeft,
          offsetMoreOrLessEquals(icons.topLeft, epsilon: .5),
        );
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets('studio modes are the top bar pills', (tester) async {
    await _show(
      tester,
      const Size(1194, 834),
      CreateStudioScreen(repository: InMemoryCharacterRepository()),
    );
    final drawing = tester.getRect(find.text('Drawing'));
    final photo = tester.getRect(find.text('Take a photo'));
    // Figma 250:2339: the pair is centred on the screen.
    final pair = tester.getRect(
      find.byKey(const ValueKey('studio-mode-switch')),
    );
    expect(pair.center.dx, closeTo(1194 / 2, 1));
    expect(photo.left, greaterThan(drawing.right));
    await tester.tap(find.text('Take a photo'));
    await tester.pumpAndSettle();
    // No camera in tests: the way round it shows instead.
    expect(find.text('이 기기에서는 카메라를 쓸 수 없어요'), findsOneWidget);
    await tester.tap(find.text('Drawing'));
    await tester.pumpAndSettle();
    expect(find.text('나의 상상 스케치북'), findsOneWidget);
  });
}
