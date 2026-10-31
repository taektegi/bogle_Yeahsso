import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/screens/house/face_map.dart';
import 'package:bogle_app/src/screens/house/figure_motion.dart';
import 'package:bogle_app/src/screens/house/figure_rig.dart';
import 'package:bogle_app/src/screens/house/house_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Rect> paintedBounds(WidgetTester tester, Key key) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    final pixels = (await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!;
    var left = image.width, top = image.height, right = -1, bottom = -1;
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        if (pixels.getUint8((y * image.width + x) * 4 + 3) < 110) continue;
        left = math.min(left, x);
        top = math.min(top, y);
        right = math.max(right, x);
        bottom = math.max(bottom, y);
      }
    }
    image.dispose();
    return Rect.fromLTRB(
      left.toDouble(),
      top.toDouble(),
      right + 1,
      bottom + 1,
    );
  }))!;
}

void main() {
  for (final id in ['mungle', 'dduchi', 'nemorin']) {
    for (final dimension in [200.0, 300.0, 420.0]) {
      testWidgets('$id plain and animated pixels match in a $dimension slot', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1000, 600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final friend = (await InMemoryCharacterRepository().fetchFriends())
            .firstWhere((friend) => friend.id == id);
        final rig = await tester.runAsync(() => rigFor(friend.assetPath));
        final face = await tester.runAsync(() => faceMapFor(friend.assetPath));
        if (id == 'mungle') expect(rig, isNotNull);
        await tester.runAsync(() => artLookOf(friend.assetPath));
        final pose = ValueNotifier(FigurePose.rest);
        addTearDown(pose.dispose);
        const plain = ValueKey('plain-art');
        const living = ValueKey('living-art');
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Row(
              children: [
                RepaintBoundary(
                  key: plain,
                  child: SizedBox.square(
                    dimension: dimension,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: FriendFigure(friend: friend),
                    ),
                  ),
                ),
                RepaintBoundary(
                  key: living,
                  child: SizedBox.square(
                    dimension: dimension,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: FriendFigure(
                        friend: friend,
                        rig: rig,
                        face: face,
                        pose: pose,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)),
        );
        await tester.pumpAndSettle();
        final before = await paintedBounds(tester, plain);
        final after = await paintedBounds(tester, living);
        expect(
          after.width,
          closeTo(before.width, 1),
          reason: '$before → $after',
        );
        expect(
          after.height,
          closeTo(before.height, 1),
          reason: '$before → $after',
        );
        expect(after.top, closeTo(before.top, 1), reason: '$before → $after');
        expect(after.left, closeTo(before.left, 1), reason: '$before → $after');
      });
    }
  }
}
