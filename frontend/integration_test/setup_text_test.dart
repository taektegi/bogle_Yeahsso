import 'package:bogle_app/src/data/character_generation.dart';
import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/screens/setup_friend_screen.dart';
import 'package:bogle_app/src/theme/bogle_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('typing a name', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildBogleTheme(),
        home: SetupFriendScreen(
          art: const GeneratedArt(
            assetPath: 'assets/figma/character_friend.svg',
          ),
          repository: InMemoryCharacterRepository(),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await binding.takeScreenshot('ipad-setup-arrive');
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('글자로 적기'));
    // Render the new field first, then finish the pill/control transitions.
    await tester.pump();
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final field = find.byKey(const ValueKey('setup-answer'));
    expect(tester.widget<TextField>(field).textAlign, TextAlign.start);
    await binding.takeScreenshot('ipad-setup-text-empty');
    await tester.enterText(find.byKey(const ValueKey('setup-answer')), '보');
    await tester.pump(const Duration(seconds: 1));
    await binding.takeScreenshot('ipad-setup-text-one');
    await tester.enterText(find.byKey(const ValueKey('setup-answer')), '보글보글이');
    await tester.pump(const Duration(seconds: 1));
    await binding.takeScreenshot('ipad-setup-text-typed');
    await tester.enterText(field, '');
    await tester.pump(const Duration(seconds: 1));
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '다음'))
          .onPressed,
      isNull,
    );
    await binding.takeScreenshot('ipad-setup-text-cleared');
    expect(tester.takeException(), isNull);
  });
}
