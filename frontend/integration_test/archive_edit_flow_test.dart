import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/screens/archive_screen.dart';
import 'package:bogle_app/src/theme/bogle_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  Future<void> shot(WidgetTester tester, String name) async {
    await tester.pump(const Duration(milliseconds: 900));
    await binding.takeScreenshot(name);
  }

  testWidgets('archive without favourites, edit and goodbye', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildBogleTheme(),
        home: ArchiveScreen(repository: InMemoryCharacterRepository()),
      ),
    );
    await shot(tester, 'ipad-archive-no-favourites');
    expect(find.byIcon(Icons.favorite_rounded), findsNothing);
    expect(find.byIcon(Icons.favorite_border_rounded), findsNothing);
    await tester.tap(find.byTooltip('뭉글이 편집'));
    await shot(tester, 'ipad-archive-edit-dialog');
    await tester.tap(find.text('취소'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byTooltip('뭉글이 삭제'));
    await shot(tester, 'ipad-archive-goodbye');
    await tester.tap(find.widgetWithText(FilledButton, '작별하기').last);
    await shot(tester, 'ipad-archive-after-goodbye');
    expect(tester.takeException(), isNull);
  });
}
