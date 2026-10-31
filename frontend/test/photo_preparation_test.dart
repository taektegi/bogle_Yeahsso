import 'dart:async';
import 'dart:ui' as ui;
import 'package:bogle_app/src/data/photo_preparation.dart';
import 'package:bogle_app/src/screens/photo_capture.dart';
import 'photo_capture_test.dart' show FakeCamera;
import 'package:bogle_app/src/screens/photo_capture/preparation_dialog.dart';
import 'package:bogle_app/src/theme/bogle_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Uint8List> photograph({
  int width = 256,
  int height = 256,
  Color background = Colors.white,
  bool subject = true,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..drawColor(background, BlendMode.src);
  if (subject) {
    canvas.drawOval(
      Rect.fromLTWH(width * .2, height * .15, width * .6, height * .7),
      Paint()..color = Colors.blue,
    );
    canvas.drawCircle(
      Offset(width * .4, height * .4),
      width * .04,
      Paint()..color = Colors.black,
    );
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  try {
    return (await image.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('실제 PNG 정규화·크기 제한과 작은 사진 거절', () async {
    final bytes = await photograph(width: 4096, height: 2048);
    final normalized = await PhotoPreparation.normalize(bytes);
    final codec = await ui.instantiateImageCodec(normalized);
    final image = (await codec.getNextFrame()).image;
    expect(
      Size(image.width.toDouble(), image.height.toDouble()),
      const Size(2048, 1024),
    );
    image.dispose();
    codec.dispose();
    final tiny = await photograph(width: 32);
    await expectLater(PhotoPreparation.normalize(tiny), throwsFormatException);
  });
  test('어두움·단색 안내는 확인하되 사진을 훼손하거나 차단하지 않는다', () async {
    final dark = await photograph(background: Colors.black, subject: false);
    final blank = await photograph(subject: false);
    expect(await PhotoPreparation.assess(dark), contains('어두워요'));
    expect(await PhotoPreparation.assess(blank), contains('대상이'));
    expect(await PhotoPreparation.normalize(blank), isNotEmpty);
    expect(await PhotoPreparation.assess(await photograph()), isNull);
  });
  testWidgets('정리 중 조작 잠금·원본 비교·명시적 채택', (tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final original = (await tester.runAsync(() => photograph()))!;
    final proposal = (await tester.runAsync(
      () => photograph(background: Colors.yellow),
    ))!;
    final pending = Completer<Uint8List>();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(PhotoPreparation.channel, (call) async {
      expect(call.arguments['bytes'], original);
      expect(call.arguments['paper'], false);
      return pending.future;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(PhotoPreparation.channel, null),
    );
    Uint8List? accepted;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildBogleTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                accepted = await showDialog<Uint8List>(
                  context: context,
                  builder: (_) => PhotoPreparationDialog(photo: original),
                );
              },
              child: const Text('사진 정리 열기'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('사진 정리 열기'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('정리해 보기'));
    await tester.tap(find.text('정리해 보기'));
    await tester.pump();
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '원본 유지'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '종이에 그린 그림'))
          .onSelected,
      isNull,
    );
    pending.complete(proposal);
    await tester.pumpAndSettle();
    await tester.tap(find.text('원본 보기'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '정리한 사진 사용'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('정리한 사진 보기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('정리한 사진 사용'));
    await tester.pumpAndSettle();
    expect(accepted, proposal);
    expect(tester.takeException(), isNull);
  });
  testWidgets('대상 채택 후 종이 그림자 없이 표시하고 원본 복원 시 프레임을 되돌린다', (tester) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final original = (await tester.runAsync(() => photograph()))!;
    final cutout = (await tester.runAsync(
      () => photograph(background: Colors.transparent),
    ))!;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      PhotoPreparation.channel,
      (_) async => cutout,
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(PhotoPreparation.channel, null),
    );
    Uint8List? submitted;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PhotoCapture(
            camera: FakeCamera.new,
            pickPhoto: () async => original,
            render: (bytes, _) async => bytes,
            onUse: (bytes) => submitted = bytes,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('photo-library')));
    await tester.pumpAndSettle();
    expect(find.byType(TornPaper), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('photo-prepare')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('정리해 보기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('정리한 사진 사용'));
    await tester.pumpAndSettle();
    expect(find.byType(TornPaper), findsNothing);
    await tester.tap(find.byKey(const ValueKey('photo-use')));
    await tester.pumpAndSettle();
    expect(submitted, cutout);
    await tester.tap(find.text('촬영 원본 복원'));
    await tester.pumpAndSettle();
    expect(find.byType(TornPaper), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('지원되지 않는 환경은 원본·수동 자르기로 복귀한다', (tester) async {
    tester.view.physicalSize = const Size(744, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final original = (await tester.runAsync(() => photograph()))!;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      PhotoPreparation.channel,
      (_) async => throw MissingPluginException(),
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(PhotoPreparation.channel, null),
    );
    await tester.pumpWidget(
      MaterialApp(home: PhotoPreparationDialog(photo: original)),
    );
    await tester.ensureVisible(find.text('정리해 보기'));
    await tester.tap(find.text('정리해 보기'));
    await tester.pumpAndSettle();
    expect(find.textContaining('이 환경에서는'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '원본 유지'))
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('제출 처리 중 회전·자르기·보정과 중복 제출을 잠근다', (tester) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final photo = (await tester.runAsync(() => photograph()))!;
    final pending = Completer<Uint8List>();
    var renders = 0, accepted = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PhotoCapture(
            camera: FakeCamera.new,
            pickPhoto: () async => photo,
            render: (bytes, edit) {
              renders++;
              return pending.future;
            },
            onUse: (_) => accepted++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('photo-library')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('사용할래요.'));
    await tester.tap(find.text('사용할래요.'));
    await tester.pump();
    for (final key in [
      'photo-turn',
      'photo-crop',
      'photo-brighten',
      'photo-prepare',
    ]) {
      final ink = find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(InkWell),
      );
      expect(tester.widget<InkWell>(ink).onTap, isNull);
    }
    expect(renders, 1);
    expect(accepted, 0);
    pending.complete(photo);
    await tester.pumpAndSettle();
    expect(accepted, 1);
    expect(tester.takeException(), isNull);
  });
}
