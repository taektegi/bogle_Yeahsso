import 'dart:ui' as ui;
import 'package:bogle_app/src/data/photo_preparation.dart';
import 'package:bogle_app/src/screens/photo_capture/preparation_dialog.dart';
import 'package:bogle_app/src/theme/bogle_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native paper perspective correction and no-key preparation preview',
    (tester) async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)
        ..drawColor(const Color(0xff222233), BlendMode.src);
      canvas.drawPath(
        Path()
          ..moveTo(90, 60)
          ..lineTo(710, 90)
          ..lineTo(660, 555)
          ..lineTo(60, 510)
          ..close(),
        Paint()..color = Colors.white,
      );
      canvas.drawOval(
        const Rect.fromLTWH(290, 170, 240, 280),
        Paint()..color = Colors.orange,
      );
      canvas.drawCircle(
        const Offset(360, 260),
        15,
        Paint()..color = Colors.black,
      );
      canvas.drawCircle(
        const Offset(460, 260),
        15,
        Paint()..color = Colors.black,
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(800, 600);
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.png,
      ))!.buffer.asUint8List();
      image.dispose();
      picture.dispose();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildBogleTheme(),
          home: PhotoPreparationDialog(photo: bytes),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('종이에 그린 그림'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('정리해 보기'));
      await tester.tap(find.text('정리해 보기'));
      await tester.pump();
      for (
        var i = 0;
        i < 80 && find.text('사진을 정리하고 있어요…').evaluate().isNotEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(find.text('정리한 사진 보기'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, '정리한 사진 사용'),
            )
            .onPressed,
        isNotNull,
      );
      await tester.pumpAndSettle();
      await binding.takeScreenshot('paper-preparation');
      var objectSegmentation = false;
      String? objectReason;
      try {
        final source = (await rootBundle.load(
          'assets/figma/home_play_character.png',
        )).buffer.asUint8List();
        final normalized = await PhotoPreparation.normalize(source);
        final object = await PhotoPreparation.prepare(
          normalized,
          paper: false,
          subject: const Offset(.65, .45),
        );
        objectSegmentation = object.isNotEmpty;
      } on PlatformException catch (error) {
        expect(error.code, 'preparation_unavailable');
        objectReason = error.details as String?;
      }
      binding.reportData = {
        ...?binding.reportData,
        'paperPerspective': true,
        'objectSegmentationAvailable': objectSegmentation,
        'objectReason': objectReason,
        'externalAiCalls': 0,
      };
      expect(tester.takeException(), isNull);
    },
  );
}
