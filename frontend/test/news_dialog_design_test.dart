import 'dart:io';
import 'dart:ui' as ui;

import 'package:bogle_app/src/theme/bogle_theme.dart';
import 'package:bogle_app/src/widgets/bogle_news_dialog.dart';
import 'package:bogle_app/src/widgets/top_bar.dart';
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
    (const Size(360, 360), 2.0),
  ]) {
    testWidgets('알림을 읽고 확인·닫기·바깥 터치로 돌아오기 $size 글자 $scale', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
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
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showBogleNews(context),
                  child: const Text('알림 열기'),
                ),
              ),
            ),
          ),
        ),
      );
      Future<void> open() async {
        await tester.tap(find.text('알림 열기'));
        await tester.pumpAndSettle();
      }

      await open();
      expect(find.text('아직 새로운 소식이 없어요.'), findsOneWidget);
      expect(find.byIcon(Icons.mark_chat_read_outlined), findsNothing);
      expect(find.byIcon(Icons.notifications_none_rounded), findsNothing);
      final dialog = tester.getRect(find.byType(Dialog));
      final confirm = find.widgetWithText(FilledButton, '확인');
      final close = find.byTooltip('알림 닫기');
      for (final target in [confirm, close]) {
        expect(tester.getSize(target).height, greaterThanOrEqualTo(48));
        expect(dialog.contains(tester.getCenter(target)), isTrue);
      }
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('CAPTURE_NEWS_DIALOG')) {
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            'artifacts/news-dialog/${size.width.toInt()}-$scale.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(find.byType(BogleNewsDialog), findsNothing);
      await open();
      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(find.byType(BogleNewsDialog), findsNothing);
      await open();
      await tester.tapAt(const Offset(2, 2));
      await tester.pumpAndSettle();
      expect(find.byType(BogleNewsDialog), findsNothing);
      expect(find.text('알림 열기'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
