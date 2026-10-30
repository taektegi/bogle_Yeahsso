import 'package:bogle_app/main.dart' as app;
import 'package:bogle_app/src/screens/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('home header on iPad and account actions', (tester) async {
    await app.main();
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await binding.takeScreenshot('ipad-home-header');
    await tester.tap(find.byKey(const ValueKey('top-action-알림')));
    await tester.pumpAndSettle();
    expect(find.text('아직 새로운 소식이 없어요.'), findsOneWidget);
    await tester.tap(find.text('확인'));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byKey(const ValueKey('top-action-마이페이지')));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileScreen), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('top-action-홈')));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const ValueKey('top-bar-icons')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
