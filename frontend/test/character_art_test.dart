import 'dart:ui' as ui;

import 'package:bogle_app/src/data/api/synced_character_repository.dart';
import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/models/character_friend.dart';
import 'package:bogle_app/src/screens/house/face_map.dart';
import 'package:bogle_app/src/screens/house/house_widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('photographed drawings are told apart from cut-out art', () {
    expect(isPhotographedArt('assets/figma/archive_nemorin.png'), isTrue);
    expect(isPhotographedArt('assets/figma/dduchi.png'), isFalse);
    expect(isPhotographedArt('assets/figma/nemorin.png'), isFalse);
    expect(isPhotographedArt('assets/figma/character_card.svg'), isFalse);
  });

  test('뚜치 is the cut-out hedgehog on a clear ground', () async {
    final friends = await InMemoryCharacterRepository().fetchFriends();
    final dduchi = friends.firstWhere((f) => f.id == 'dduchi');
    expect(dduchi.assetPath, 'assets/figma/dduchi.png');
    expect(isPhotographedArt(dduchi.assetPath), isFalse);
    final bytes = await rootBundle.load(dduchi.assetPath);
    expect(bytes.lengthInBytes, greaterThan(0));
  });

  test('네모린 uses the supplied transparent character, not a photo', () async {
    final friends = await InMemoryCharacterRepository().fetchFriends();
    final nemorin = friends.firstWhere((f) => f.id == 'nemorin');
    expect(nemorin.assetPath, 'assets/figma/nemorin.png');
    expect(isPhotographedArt(nemorin.assetPath), isFalse);
    final bytes = await rootBundle.load(nemorin.assetPath);
    final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      expect(image.width, 423);
      expect(image.height, 764);
      final rgba = (await image.toByteData())!;
      for (final pixel in [
        0,
        image.width - 1,
        image.width * image.height - 1,
      ]) {
        expect(
          rgba.getUint8(pixel * 4 + 3),
          0,
          reason: 'The background must stay transparent',
        );
      }
      expect(rgba.getUint8((500 * image.width + 200) * 4 + 3), 255);
    } finally {
      image.dispose();
      codec.dispose();
    }
  });

  test('뽀직뽀직, 민들레 and 귤이 are fixed starters: transparent PNGs that '
      'blink, chew and blush', () async {
    final friends = {
      for (final f in await InMemoryCharacterRepository().fetchFriends())
        f.id: f,
    };
    for (final (id, name, accent) in [
      ('ppojik', '뽀직뽀직', 0xFFFED6FF),
      ('mindle', '민들레', 0xFFB0D8A5),
      ('gyuri', '귤이', 0xFFB8E7FF),
    ]) {
      final friend = friends[id]!;
      expect(friend.name, name);
      expect(friend.accentHex, accent);
      expect(friend.assetPath, 'assets/figma/$id.png');
      expect(SyncedCharacterRepository.isServiceId(id), isFalse);
      expect(isPhotographedArt(friend.assetPath), isFalse);

      final face = (await faceMapFor(friend.assetPath))!;
      expect(face.facing, 0, reason: name);
      // Both eyes are on the drawing, so both blink.
      expect(face.eyes, hasLength(2), reason: name);
      expect(face.cheeks, hasLength(2), reason: name);
      expect(face.mouth, isNotNull, reason: name);
      final anchors = await anchorsFor(friend.assetPath);
      expect(anchors.mouth, isNotNull, reason: name);
      expect(anchors.mouth!.center.dx, closeTo(.5, .12), reason: name);
    }
  });
}
