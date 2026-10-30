import 'dart:io';
import 'dart:ui' as ui;

import 'package:bogle_app/src/data/character_generation.dart';
import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/data/speech_style.dart';
import 'package:bogle_app/src/screens/house/house_widgets.dart';
import 'package:bogle_app/src/screens/setup_friend_screen.dart';
import 'package:bogle_app/src/theme/bogle_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const capture = bool.fromEnvironment('CAPTURE_SPEECH_DESIGN');
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await anchorsFor('assets/figma/character_friend.svg');
    if (capture) {
      for (final (family, path) in [
        ('Yangjin', 'assets/fonts/Yangjin.ttf'),
        ('Pretendard', 'assets/fonts/Pretendard-Regular.otf'),
        ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
      ]) {
        await (FontLoader(family)..addFont(rootBundle.load(path))).load();
      }
    }
  });

  for (final (size, textScale) in [
    (const Size(1024, 768), 1.0),
    (const Size(1194, 834), 1.0),
    (const Size(1366, 1024), 1.0),
    (const Size(744, 600), 2.0),
  ]) {
    testWidgets('말투 설정 중앙 배치와 네 가지 직접 선택 $size 글자 $textScale', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final boundary = GlobalKey();
      final fontScale = ValueNotifier(textScale);
      addTearDown(fontScale.dispose);
      final repo = InMemoryCharacterRepository();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildBogleTheme(),
            builder: (context, child) => ValueListenableBuilder<double>(
              valueListenable: fontScale,
              builder: (context, scale, _) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  disableAnimations: true,
                  textScaler: TextScaler.linear(scale),
                ),
                child: child!,
              ),
            ),
            home: SetupFriendScreen(
              repository: repo,
              art: const GeneratedArt(
                assetPath: 'assets/figma/character_friend.svg',
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('글자로 적기'));
      await tester.tap(find.text('글자로 적기'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('setup-answer')), '말랑');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.widgetWithText(FilledButton, '다음'));
      await tester.tap(find.widgetWithText(FilledButton, '다음'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('다정한 응원가'));
      await tester.tap(find.text('다정한 응원가'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('setup-next')));
      await tester.tap(find.byKey(const ValueKey('setup-next')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('구름 구경하기'));
      await tester.tap(find.text('구름 구경하기'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('setup-next')));
      await tester.tap(find.byKey(const ValueKey('setup-next')));
      await tester.pumpAndSettle();
      fontScale.value = textScale;
      await tester.pumpAndSettle();
      expect(find.text('공손한 말'), findsNothing);
      expect(find.text('편한 말'), findsNothing);
      expect(find.byType(ChoiceChip), findsNothing);
      final confirm = find.byKey(const ValueKey('setup-befriend'));
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      if (textScale == 1) {
        final art = tester.getRect(find.bySemanticsLabel('새 친구').first);
        expect(art.center.dx, closeTo(size.width / 2, 1));
        final cards = [
          for (final m in SpeechManner.values)
            tester.getRect(find.byKey(ValueKey('speech-manner-${m.name}'))),
        ];
        for (final card in cards) {
          expect(card.top, closeTo(cards.first.top, 1));
          expect(card.top, greaterThan(art.bottom));
          expect(card.left, greaterThanOrEqualTo(0));
          expect(card.right, lessThanOrEqualTo(size.width));
        }
      }
      for (final manner in SpeechManner.values) {
        final card = find.byKey(ValueKey('speech-manner-${manner.name}'));
        await tester.ensureVisible(card);
        await tester.tap(card);
        await tester.pumpAndSettle();
        expect(
          tester.widget<SpeechBubble>(find.byType(SpeechBubble)).text,
          SpeechProfile(manner).preview(SpeechSample.play),
        );
      }
      await tester.ensureVisible(confirm);
      expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
      if (capture) {
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final folder = Directory('artifacts/figma-speech-reference')
            ..createSync(recursive: true);
          await File(
            '${folder.path}/implemented-${size.width.toInt()}-$textScale.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(
        (await repo.fetchFriends())
            .firstWhere((f) => f.name == '말랑')
            .speechStyle,
        'robot_casual',
      );
      for (
        var i = 0;
        i < 4 &&
            find.byKey(const ValueKey('greeting-box')).evaluate().isNotEmpty;
        i++
      ) {
        final greeting = find.byKey(const ValueKey('greeting-box'));
        await tester.ensureVisible(greeting);
        await tester.tap(greeting);
        await tester.pumpAndSettle();
      }
      expect(find.text('말랑의 집으로 가기'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
