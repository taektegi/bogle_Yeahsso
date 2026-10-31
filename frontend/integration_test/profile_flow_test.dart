import 'package:bogle_app/main.dart' as app;
import 'package:bogle_app/src/screens/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  Future<void> capture(WidgetTester tester, String name) async {
    await tester.pump(const Duration(milliseconds: 600));
    await binding.takeScreenshot(name);
  }

  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      240,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('profile-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('landscape my page: sections without likes, orders, edit', (
    tester,
  ) async {
    await app.main();
    // Home has a deliberate idle animation, so do not pumpAndSettle there.
    await tester.pump(const Duration(seconds: 3));
    await tester.tap(find.byTooltip('마이페이지'));
    await tester.pumpAndSettle();
    await capture(tester, 'ipad-profile-top');

    expect(find.byIcon(Icons.favorite_rounded), findsNothing);
    expect(find.byIcon(Icons.favorite_border_rounded), findsNothing);
    await scrollTo(tester, find.text('이전 주문 내역'));
    await capture(tester, 'ipad-profile-orders');
    await scrollTo(tester, find.text('이용약관 및 개인정보처리방침'));
    await capture(tester, 'ipad-profile-bottom');

    await tester.tap(find.text('계정 관리'));
    await tester.pumpAndSettle();
    await capture(tester, 'ipad-profile-editor');
    await tester.enterText(
      find.byKey(const ValueKey('profile-nickname')),
      '별빛',
    );
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('top-action-홈')));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byTooltip('마이페이지'));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(find.text('안녕, 별빛!'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
