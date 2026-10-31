import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bogle_app/src/data/art_source.dart';
import 'package:bogle_app/src/models/character_friend.dart';
import 'package:bogle_app/src/screens/house/face_map.dart';
import 'package:bogle_app/src/screens/house/figure_motion.dart';
import 'package:bogle_app/src/screens/house/house_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A picture the way a character generator hands it over: one figure in
/// the middle of a clear square canvas, with air under its feet, and a face
/// map beside it.
Future<String> generatedFriend() async {
  final dir = await Directory.systemTemp.createTemp('bogle_generated');
  final recorder = ui.PictureRecorder();
  Canvas(recorder)
    ..drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(60, 40, 140, 160),
        const Radius.circular(60),
      ),
      Paint()..color = const Color(0xFFF7BC8E),
    )
    ..drawCircle(const Offset(105, 105), 9, Paint()..color = Colors.black87)
    ..drawCircle(const Offset(155, 105), 9, Paint()..color = Colors.black87);
  final image = await recorder.endRecording().toImage(256, 256);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  final path = '${dir.path}/friend.png';
  await File(path).writeAsBytes(png!.buffer.asUint8List());
  await File('${dir.path}/friend.face.json').writeAsString(
    jsonEncode({
      'version': 1,
      'size': [256, 256],
      'facing': 'front',
      'head': [60, 40, 140, 120],
      'eyes': [
        [105, 105, 9],
        [155, 105, 9],
      ],
      'mouth': [130, 135, 30, 10],
      'cheeks': [
        [88, 128, 12],
        [172, 128, 12],
      ],
    }),
  );
  return path;
}

void main() {
  late String art;
  setUpAll(() async => art = await generatedFriend());

  for (final act in [
    Act.float,
    Act.jelly,
    Act.peekaboo,
    Act.freeze,
    Act.sneak,
    Act.startle,
    Act.heartbeat,
    Act.dizzy,
    Act.puff,
    Act.waddle,
    Act.popcorn,
    Act.yahoo,
    Act.proud,
  ]) {
    testWidgets('a generated friend plays $act with its face drawn moving', (
      tester,
    ) async {
      // Read the picture and its face as the house does, before it shows.
      await tester.runAsync(() async {
        await faceMapFor(art);
        await artCropOf(art);
      });
      final friend = CharacterFriend(
        id: 'made',
        name: '코코',
        personality: '다정하고 잘 웃어요',
        favoriteThings: const ['낮잠'],
        speechStyle: '해요체',
        assetPath: art,
        accentHex: 0xFFF4C29E,
      );
      var done = false;
      final key = GlobalKey<State<LivingCharacter>>();
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: LivingCharacter(
              key: key,
              friend: friend,
              asleep: false,
              reaction: Reaction.none,
              reactionId: 0,
              onTap: () {},
              size: 300,
              cue: FigureCue(act, onDone: () => done = true),
            ),
          ),
        ),
      );
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
      // Its face is drawn over the picture (a flat picture's only way to
      // move its eyes and mouth).
      expect(
        find.byWidgetPredicate(
          (w) => w is CustomPaint && w.foregroundPainter is FacePainter,
        ),
        findsOneWidget,
      );

      final poses = <FigurePose>[];
      final state = key.currentState! as dynamic;
      for (var t = 0.0; t < actLength(act) + .6; t += 1 / 30) {
        await tester.pump(const Duration(milliseconds: 33));
        poses.add(state.debugPose as FigurePose);
      }
      expect(tester.takeException(), isNull);
      expect(done, isTrue, reason: 'the act plays to its end');
      // The whole body acts, not just arms it doesn't have.
      final moved = poses.any(
        (p) =>
            p.dy.abs() > .02 ||
            p.dx.abs() > .02 ||
            (p.scaleY - 1).abs() > .06 ||
            p.tilt.abs() > .08,
      );
      expect(moved, isTrue);
      // And the face shows it: eyes shut or wide, or a flush, at some point.
      expect(
        poses.any((p) => p.eyes < .4 || p.eyes > 1.1 || p.cheeks > .5),
        isTrue,
      );
    });
  }
}
