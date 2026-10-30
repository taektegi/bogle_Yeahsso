import 'dart:io';
import 'dart:ui' as ui;
import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/data/photo_preparation.dart';
import 'package:bogle_app/src/screens/create_studio_screen.dart';
import 'package:bogle_app/src/theme/bogle_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'photo_capture_test.dart' show FakeCamera;
import 'photo_preparation_test.dart' show photograph;

void main() {
  const capture = bool.fromEnvironment('CAPTURE_PHOTO_DESIGN');
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
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
    testWidgets('사진 도구의 균형·분리된 대상 선택·모달 $size 글자 $scale', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final photo = (await tester.runAsync(() => photograph()))!;
      final boundary = GlobalKey();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        PhotoPreparation.channel,
        (_) async => photo,
      );
      addTearDown(
        () =>
            messenger.setMockMethodCallHandler(PhotoPreparation.channel, null),
      );
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildBogleTheme(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                disableAnimations: true,
                textScaler: TextScaler.linear(scale),
              ),
              child: child!,
            ),
            home: CreateStudioScreen(
              repository: InMemoryCharacterRepository(),
              camera: () => FakeCamera(photo: photo),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('studio-mode-photo')));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('사진 찍기'));
      await tester.pumpAndSettle();
      Future<void> shot(String name) async {
        if (!capture) return;
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
        await tester.runAsync(() async {
          final rendered =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final data = await rendered.toByteData(
            format: ui.ImageByteFormat.png,
          );
          final folder = Directory('artifacts/photo-design')
            ..createSync(recursive: true);
          await File(
            '${folder.path}/$name-${size.width.toInt()}-$scale.png',
          ).writeAsBytes(data!.buffer.asUint8List());
          rendered.dispose();
        });
      }

      final rects = [
        for (final key in ['photo-turn', 'photo-crop', 'photo-brighten'])
          tester.getRect(find.byKey(ValueKey(key))),
      ];
      for (final rect in rects) {
        expect(rect.width, closeTo(rects.first.width, .01));
        expect(rect.height, closeTo(rects.first.height, .01));
      }
      final entry = find.byKey(const ValueKey('photo-prepare'));
      expect(tester.getRect(entry).top, greaterThan(rects.last.bottom));
      await shot('editing');
      await tester.ensureVisible(entry);
      await tester.runAsync(() async {
        await tester.tap(entry);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('어떤 친구로 만들까요?'), findsOneWidget);
      expect(find.byType(FilledButton), findsWidgets);
      expect(find.text('정리한 사진 사용'), findsNothing);
      await shot('select');
      await tester.ensureVisible(find.text('정리해 보기'));
      await tester.tap(find.text('정리해 보기'));
      await tester.pumpAndSettle();
      expect(find.text('정리해 보기'), findsNothing);
      expect(find.text('정리한 사진 사용'), findsOneWidget);
      await shot('compare');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
