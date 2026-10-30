import 'dart:io';
import 'dart:ui' as ui;

import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/screens/archive_screen.dart';
import 'package:bogle_app/src/theme/bogle_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    for (final (family, path) in [
      ('Yangjin', 'assets/fonts/Yangjin.ttf'),
      ('Pretendard', 'assets/fonts/Pretendard-Regular.otf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
    ]) {
      await (FontLoader(family)..addFont(rootBundle.load(path))).load();
    }
  });
  for (final (size, scale) in [
    (const Size(1366, 1024), 1.0),
    (const Size(1024, 768), 1.0),
    (const Size(744, 600), 2.0),
  ]) {
    testWidgets('친구 편집의 글꼴·키보드·취소·저장 $size 글자 $scale', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repo = InMemoryCharacterRepository();
      final original = (await repo.fetchFriends()).first;
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildBogleTheme(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale),
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: ArchiveScreen(repository: repo),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> open() async {
        await tester.tap(find.byTooltip('뭉글이 편집'));
        await tester.pumpAndSettle();
      }

      Future<void> shot(String suffix) async {
        if (!const bool.fromEnvironment('CAPTURE_ARCHIVE_EDITOR')) return;
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            'artifacts/archive-editor/${size.width.toInt()}-$scale-$suffix.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }

      await open();
      expect(find.text('친구 정보 수정'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('edit-name')))
            .style!
            .fontFamily,
        bogleUiFont,
      );
      await shot('opened');
      await tester.enterText(find.byKey(const ValueKey('edit-name')), '취소할 이름');
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect((await repo.fetchFriends()).first.name, original.name);
      await open();
      await tester.enterText(find.byKey(const ValueKey('edit-name')), '   ');
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '저장'))
            .onPressed,
        isNull,
      );
      await tester.enterText(find.byKey(const ValueKey('edit-name')), '구름친구');
      tester.view.viewInsets = const FakeViewPadding(bottom: 240);
      await tester.pumpAndSettle();
      final save = find.widgetWithText(FilledButton, '저장');
      expect(tester.getRect(save).bottom, lessThanOrEqualTo(size.height - 240));
      expect(tester.getSize(save).height, greaterThanOrEqualTo(48));
      await tester.ensureVisible(
        find.byKey(const ValueKey('edit-introduction')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('edit-introduction')),
        '구름 구경을 좋아하는 친구야.',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('speech-manner-plain')),
      );
      await tester.tap(find.byKey(const ValueKey('speech-manner-plain')));
      await tester.ensureVisible(find.text('편한 말'));
      await tester.tap(find.text('편한 말'));
      await tester.pumpAndSettle();
      await shot('keyboard');
      await tester.tap(save);
      await tester.pumpAndSettle();
      final saved = (await repo.fetchFriends()).first;
      expect(saved.name, '구름친구');
      expect(saved.introduction, '구름 구경을 좋아하는 친구야.');
      expect(saved.personality, original.personality);
      expect(saved.speechStyle, 'plain_casual');
      expect(find.byKey(const ValueKey('edit-friend-dialog')), findsNothing);
      tester.view.resetViewInsets();
      expect(tester.takeException(), isNull);
    });
  }
}
