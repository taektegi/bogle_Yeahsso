import 'package:bogle_app/src/widgets/startup_artwork.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('startup bubbles rise on iPad without moving the logo', (
    tester,
  ) async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: StartupArtwork())),
    );
    final bubble = find.byKey(const ValueKey('startup-bubble-2'));
    for (var i = 0; i < 40 && bubble.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(bubble, findsOneWidget);
    final logo = find.byKey(const ValueKey('startup-wordmark'));
    final logoRect = tester.getRect(logo);
    double y() => tester.widget<Transform>(bubble).transform.entry(1, 3);
    final before = y();
    await binding.takeScreenshot('ipad-startup-motion-before');
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(y(), lessThan(before - 15));
    expect(tester.getRect(logo), logoRect);
    await binding.takeScreenshot('ipad-startup-motion-after');
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });
}
