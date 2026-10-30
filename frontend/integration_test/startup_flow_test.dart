import 'package:bogle_app/main.dart' as app;
import 'package:bogle_app/src/screens/home_screen.dart';
import 'package:bogle_app/src/screens/startup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('cold launch then home, with no startup on return', (
    tester,
  ) async {
    await app.main();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(StartupScreen), findsOneWidget);
    await binding.takeScreenshot('ipad-startup');
    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('startup-overlay')), findsNothing);
    await binding.takeScreenshot('ipad-startup-home');
    await tester.tap(find.text('친구 그리기 / 사진찍기'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('top-action-홈')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const ValueKey('startup-overlay')), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
