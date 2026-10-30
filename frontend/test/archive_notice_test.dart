import 'dart:io';
import 'dart:ui' as ui;

import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/data/starter_friends.dart';
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
    (const Size(744, 600), 2.0),
  ]) {
    testWidgets('작별 알림은 읽고 복구할 시간을 준 뒤 자동으로 닫힘 $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final friends = InMemoryCharacterRepository();
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
            home: ArchiveScreen(repository: friends),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> goodbye() async {
        await tester.tap(find.byTooltip('뭉글이 삭제'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, '작별하기').last);
        await tester.pumpAndSettle();
      }

      await goodbye();
      expect(find.text('뭉글이와 작별했어요'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final notice = tester.getRect(
        find
            .descendant(
              of: find.byType(SnackBar),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(notice.left, greaterThanOrEqualTo(16));
      expect(notice.right, lessThanOrEqualTo(size.width - 16));
      expect(
        tester.getSize(find.widgetWithText(TextButton, '다시 데려오기')).height,
        greaterThanOrEqualTo(48),
      );
      if (scale > 1.4) {
        expect(
          tester.getRect(find.text('다시 데려오기')).top,
          greaterThan(tester.getRect(find.text('뭉글이와 작별했어요')).bottom),
        );
      }
      if (const bool.fromEnvironment('CAPTURE_ARCHIVE_NOTICE')) {
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            'artifacts/archive-notice/${size.width.toInt()}.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pump(const Duration(seconds: 4));
      expect(find.text('다시 데려오기'), findsOneWidget);
      await tester.tap(find.text('다시 데려오기'));
      await tester.pumpAndSettle();
      expect(await friends.fetchFriends(), hasLength(starterFriends().length));
      expect(find.text('뭉글이의 집에 놀러 가기'), findsOneWidget);

      await goodbye();
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      expect(
        await friends.fetchFriends(),
        hasLength(starterFriends().length - 1),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
