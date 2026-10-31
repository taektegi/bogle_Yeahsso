import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bogle_app/src/data/art_source.dart';
import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/models/character_friend.dart';
import 'package:bogle_app/src/screens/friend_screen.dart';
import 'package:bogle_app/src/screens/house/face_map.dart';
import 'package:bogle_app/src/screens/house/house_widgets.dart';
import 'package:bogle_app/src/theme/bogle_theme.dart';
import 'package:bogle_app/src/widgets/bogle_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Artwork the character service might hand over, saved to files.
late String cutOutPng, cutOutSvg, paintedPng;
const brokenUrl = 'https://example.invalid/friends/42.png';

Future<String> _save(Directory dir, String name, List<int> bytes) async {
  final file = File('${dir.path}/$name');
  await file.writeAsBytes(bytes);
  return file.path;
}

/// A picture that came with its own background: a square, painted edge to
/// edge.
Future<List<int>> _painted() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder)
    ..drawRect(
      const Rect.fromLTWH(0, 0, 64, 64),
      Paint()..color = const Color(0xFFFFF4D6),
    )
    ..drawCircle(const Offset(32, 32), 18, Paint()..color = Colors.orange);
  final image = await recorder.endRecording().toImage(64, 64);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  return png!.buffer.asUint8List();
}

CharacterFriend _friend(String id, String art) => CharacterFriend(
  id: id,
  name: '새친구',
  personality: '다정하고 잘 웃어요',
  favoriteThings: const ['사과'],
  speechStyle: '해요체',
  assetPath: art,
  accentHex: 0xFFBDCFFF,
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final dir = await Directory.systemTemp.createTemp('bogle_art');
    Future<List<int>> asset(String path) async =>
        (await rootBundle.load(path)).buffer.asUint8List();
    cutOutPng = await _save(
      dir,
      'friend.png',
      await asset('assets/figma/nemorin.png'),
    );
    cutOutSvg = await _save(
      dir,
      'friend.svg',
      await asset('assets/figma/character_friend.svg'),
    );
    paintedPng = await _save(dir, 'painted.png', await _painted());
  });

  test('where artwork comes from, and what kind it is', () {
    expect(artOriginOf('assets/figma/dduchi.png'), ArtOrigin.asset);
    expect(artOriginOf('/var/mobile/friend.png'), ArtOrigin.file);
    expect(artOriginOf('file:///var/mobile/friend.png'), ArtOrigin.file);
    expect(artOriginOf('https://cdn.bogle.app/f.svg?v=2'), ArtOrigin.network);
    expect(isSvgArt('https://cdn.bogle.app/f.SVG?v=2'), isTrue);
    expect(isPngArt('https://cdn.bogle.app/f.png#x'), isTrue);
    expect(
      artSibling('https://cdn.bogle.app/f.png?v=2', '.png', '.face.json'),
      'https://cdn.bogle.app/f.face.json?v=2',
    );
  });

  test('cut-out art from a file is measured; art with a background is a '
      'card; unreadable art is neither', () async {
    final png = (await artLookOf(cutOutPng))!;
    expect(png.clearGround, isTrue);
    expect(png.natural.width, greaterThan(0));
    expect(png.drawn.isEmpty, isFalse);
    expect(await standsAsCard(cutOutPng), isFalse);
    expect((await artLookOf(cutOutSvg))!.clearGround, isTrue);

    expect((await artLookOf(paintedPng))!.clearGround, isFalse);
    expect(await standsAsCard(paintedPng), isTrue);
    expect(await artBounds(paintedPng), const Rect.fromLTWH(0, 0, 1, 1));

    expect(await artLookOf(brokenUrl), isNull);
    expect(await standsAsCard(brokenUrl), isFalse);
  });

  test("a generator's square canvas is cut to its figure, feet on the "
      'floor, and its face moves along; snug art is kept', () async {
    // A clear 200 × 200 canvas with the figure in the middle and 50 px of
    // air under its feet: standing bottom-centred, it would float.
    final dir = await Directory.systemTemp.createTemp('bogle_cut');
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      const Rect.fromLTWH(50, 30, 100, 120),
      Paint()..color = Colors.orange,
    );
    final image = await recorder.endRecording().toImage(200, 200);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final made = await _save(dir, 'made.png', png!.buffer.asUint8List());
    await File(made.replaceFirst('.png', '.face.json')).writeAsString(
      jsonEncode({
        'version': 1,
        'size': [200, 200],
        'facing': 'front',
        'eyes': [
          [100, 80, 6],
        ],
        'mouth': [100, 110, 30, 10],
      }),
    );

    final crop = (await artCropOf(made))!;
    final cut = Rect.fromLTRB(
      crop.left * 200,
      crop.top * 200,
      crop.right * 200,
      crop.bottom * 200,
    );
    // Right under the feet (the last solid row is 149), a little air around.
    expect(cut.bottom, closeTo(151, .01));
    expect(cut.top, lessThan(30));
    expect(cut.left, lessThan(50));
    expect(cut.right, greaterThan(150));

    final codec = await ui.instantiateImageCodec(await loadArtBytes(made));
    final shown = (await codec.getNextFrame()).image;
    expect(shown.width, cut.width.round());
    expect(shown.height, cut.height.round());
    final pixels = (await shown.toByteData())!;
    final feet = ((shown.height - 2) * shown.width + shown.width ~/ 2) * 4;
    expect(
      pixels.getUint8(feet + 3),
      255,
      reason: 'the figure reaches the floor',
    );

    final face = (await faceMapFor(made))!;
    expect(face.size, cut.size);
    expect(face.mouth!.center, const Offset(100, 110) - cut.topLeft);
    expect(face.eyes.single.$1, const Offset(100, 80) - cut.topLeft);

    expect(await artCropOf(cutOutPng), isNull, reason: '네모린 is snug');
    expect(await artCropOf(paintedPng), isNull, reason: 'it has a ground');
    expect(await artCropOf(cutOutSvg), isNull);
  });

  testWidgets('the invite tile shows a generated friend wherever it comes '
      'from, and 뭉글이 when it has no outline to take', (tester) async {
    Future<Finder> tile(String art) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: FriendSilhouette(
              key: ValueKey(art),
              assetPath: art,
              size: const Size(48, 40),
            ),
          ),
        ),
      );
      await _settle(tester);
      return find.byType(FriendSilhouette);
    }

    for (final art in [cutOutPng, cutOutSvg]) {
      expect(
        find.descendant(
          of: await tile(art),
          matching: find.byKey(ValueKey('silhouette-$art')),
        ),
        findsOneWidget,
        reason: art,
      );
    }
    for (final art in [paintedPng, brokenUrl]) {
      expect(
        find.descendant(
          of: await tile(art),
          matching: find.byKey(
            const ValueKey('silhouette-${FriendSilhouette.fallback}'),
          ),
        ),
        findsOneWidget,
        reason: art,
      );
    }
  });

  testWidgets('a broken link shows the new-friend drawing, not a hole', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 100,
          height: 100,
          child: FriendArtwork(assetPath: brokenUrl),
        ),
      ),
    );
    await _settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.byType(FriendArtwork), findsOneWidget);
  });

  for (final art in ['file', 'painted', 'broken']) {
    testWidgets('a friend whose art is $art lives in its house', (
      tester,
    ) async {
      final path = switch (art) {
        'file' => cutOutPng,
        'painted' => paintedPng,
        _ => brokenUrl,
      };
      final repo = InMemoryCharacterRepository();
      final friend = _friend('new-$art', path);
      await repo.saveFriend(friend);
      tester.view.physicalSize = const Size(1194, 834);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildBogleTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: FriendScreen(
            repository: repo,
            friend: friend,
            clock: () => DateTime(2026, 9, 28, 14),
          ),
        ),
      );
      await _settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.bySemanticsLabel('새친구 쓰다듬기'), findsOneWidget);
      expect(find.bySemanticsLabel('초대하기'), findsOneWidget);
      // It can still eat.
      await tester.tap(find.bySemanticsLabel('간식주기'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel(RegExp('^쿠키 주기')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
