import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/screens/create_studio_screen.dart';
import 'package:bogle_app/src/theme/bogle_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('sketchbook colour controls on iPad', (tester) async {
    Future<void> shot(String name) async {
      for (var i = 0; i < 35; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await binding.takeScreenshot(name);
    }

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildBogleTheme(),
        home: CreateStudioScreen(repository: InMemoryCharacterRepository()),
      ),
    );
    await tester.pumpAndSettle();
    final center = tester.getCenter(
      find.byKey(const ValueKey('drawing-canvas')),
    );
    await tester.timedDragFrom(
      center - const Offset(150, 0),
      const Offset(200, 70),
      const Duration(milliseconds: 400),
    );
    await shot('ipad-studio-line-widths');
    await tester.tap(find.byTooltip('색상'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('color-cell-6-3')));
    await shot('ipad-studio-color-grid');
    await tester.tap(find.text('스펙트럼'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('color-spectrum')));
    await shot('ipad-studio-color-spectrum');
    await tester.tap(find.text('슬라이더'));
    await tester.pumpAndSettle();
    await shot('ipad-studio-color-sliders');
    await tester.tap(find.byTooltip('그림에서 색상 추출'));
    await tester.pumpAndSettle();
    await tester.tapAt(center - const Offset(100, -17.5));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 400)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('studio-colors')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
