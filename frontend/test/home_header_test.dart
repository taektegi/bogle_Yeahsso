import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/screens/home_screen.dart';
import 'package:bogle_app/src/screens/profile_screen.dart';
import 'package:bogle_app/src/theme/bogle_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> openHome(WidgetTester tester, Size size, double scale) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildBogleTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: true,
          textScaler: TextScaler.linear(scale),
        ),
        child: child!,
      ),
      home: HomeScreen(repository: InMemoryCharacterRepository()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final size in const [
    Size(1024, 768),
    Size(1194, 834),
    Size(1366, 1024),
  ]) {
    for (final scale in [1.0, 1.6]) {
      testWidgets('Figma 243:2201 layout holds at $size / $scale', (
        tester,
      ) async {
        await openHome(tester, size, scale);
        Rect rect(String key) => tester.getRect(find.byKey(ValueKey(key)));
        final brand = rect('home-brand');
        final welcome = rect('home-welcome');
        final icons = rect('top-bar-icons');
        final play = rect('home-play-card');

        // One header row: logo left, welcome centred, icons right, all
        // lined up with the cards' outer edges.
        expect(welcome.center.dx, closeTo(size.width / 2, .5));
        expect(icons.center.dy, closeTo(brand.center.dy, .5));
        expect(welcome.center.dy, closeTo(brand.center.dy, .5));
        expect(brand.left, closeTo(play.left, .5));
        expect(size.width - icons.right, closeTo(brand.left, .5));
        expect(welcome.left, greaterThan(brand.right));
        expect(icons.left, greaterThan(welcome.right));

        // Cards in the Figma proportions: the tall one on the left, two
        // stacked on the right, 48/1194 of the width apart.
        final draw = tester.getRect(find.bySemanticsLabel('친구 그리기 또는 사진찍기'));
        final order = tester.getRect(find.bySemanticsLabel('굿즈 주문하기'));
        // On the Figma frame's own shape the card matches it exactly; on
        // 4:3 screens the cards use the extra height and grow taller.
        if (size == const Size(1194, 834)) {
          expect(play.width / play.height, closeTo(536 / 468, .08));
        }
        expect(draw.top, closeTo(play.top, 1));
        expect(order.bottom, closeTo(play.bottom, 1));
        expect(draw.left - play.right, closeTo(size.width * 48 / 1194, 2));
        expect(draw.height, closeTo(order.height, 1));
        expect(play.top, greaterThan(brand.bottom));

        for (final label in ['홈', '알림', '마이페이지']) {
          final bounds = rect('top-action-$label');
          expect(bounds.height, greaterThanOrEqualTo(48));
          expect(bounds.width, greaterThanOrEqualTo(48));
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('header icons: home marks where you are, news and settings', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await openHome(tester, const Size(1024, 768), 1);
    for (final label in ['홈', '알림', '마이페이지']) {
      expect(find.bySemanticsLabel(label), findsOneWidget);
    }
    semantics.dispose();
    await tester.tap(find.byKey(const ValueKey('top-action-홈')));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('top-action-알림')));
    await tester.pumpAndSettle();
    expect(find.text('아직 새로운 소식이 없어요.'), findsOneWidget);
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('top-action-마이페이지')));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileScreen), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('top-action-홈')));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
