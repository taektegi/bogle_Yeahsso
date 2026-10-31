import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bogle_app/src/data/app_services.dart';
import 'package:bogle_app/src/data/character_generation.dart';
import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/data/profile_repository.dart';
import 'package:bogle_app/src/data/window_view.dart';
import 'package:bogle_app/src/models/character_friend.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A [width] × [height] PNG, clear except for a [ink] square of colour.
Future<Uint8List> page(int width, int height, Rect ink) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(ink, Paint()..color = const Color(0xFF3A4A8C));
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  picture.dispose();
  image.dispose();
  return png!.buffer.asUint8List();
}

Future<Size> sizeOf(List<int> bytes) async {
  final codec = await ui.instantiateImageCodec(Uint8List.fromList(bytes));
  final image = (await codec.getNextFrame()).image;
  final size = Size(image.width.toDouble(), image.height.toDouble());
  image.dispose();
  codec.dispose();
  return size;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the app starts with its six friends and nothing else', () async {
    final services = AppServices.local();
    expect((await services.characters.fetchFriends()).map((f) => f.name), [
      '뭉글이',
      '뚜치',
      '네모린',
      '뽀직뽀직',
      '민들레',
      '귤이',
    ]);
    expect(await services.orders.fetchOrders(), isEmpty);
    expect(await services.orders.fetchAddresses(), isEmpty);
    expect(
      (await services.profile.fetchProfile()).nickname,
      UserProfile.defaultNickname,
    );
  });

  test('a new friend gets its id and creation time from the store', () async {
    final repository = InMemoryCharacterRepository();
    final created = await repository.createFriend(
      const NewFriend(
        name: '구름이',
        personality: '느긋해요',
        favoriteThings: ['구름'],
        speechStyle: '해요체',
        assetPath: '/tmp/friend.png',
        accentHex: 0xFFBDCFFF,
      ),
    );
    expect(created.id, isNotEmpty);
    expect(created.createdAt, isNotNull);
    expect((await repository.fetchFriends()).last.id, created.id);
  });

  test('a friend reads back what it writes', () {
    final friend = CharacterFriend(
      id: 'a1',
      name: '구름이',
      personality: '느긋해요',
      introduction: '하늘에서 왔어',
      favoriteThings: const ['구름', '사과'],
      speechStyle: '해요체',
      assetPath: 'https://example.com/a1.png',
      accentHex: 0xFFBDCFFF,
      level: 3,
      memories: 7,
      createdAt: DateTime.utc(2026, 10, 8, 5),
      sleep: const SleepSchedule(bedtime: 22 * 60, wakeTime: 6 * 60),
      view: const WindowView(day: 'https://example.com/day.png'),
    );
    final back = CharacterFriend.fromJson(friend.toJson());
    expect(back.toJson(), friend.toJson());
  });

  test('without a character service the drawing itself becomes the friend, '
      'cut to its strokes', () async {
    final drawing = await page(
      1000,
      600,
      const Rect.fromLTWH(400, 200, 100, 80),
    );
    final art = await const LocalCharacterGenerator()
        .start(GenerationInput(drawing, source: GenerationSource.drawing))
        .result;
    expect(art.accentHex, GeneratedArt.defaultAccent);
    final file = File(art.assetPath);
    expect(file.path, endsWith('.png'));
    final size = await sizeOf(await file.readAsBytes());
    // The 100 × 80 strokes with a little air, not the 1000 × 600 page.
    expect(size.width, inInclusiveRange(100, 130));
    expect(size.height, inInclusiveRange(80, 110));
  });

  test('a cancelled generation never hands over its artwork', () async {
    final job = const LocalCharacterGenerator().start(
      GenerationInput(
        Uint8List.fromList([0xFF, 0xD8, 0xFF, 0, 0, 0, 0, 0, 0]),
        source: GenerationSource.photo,
      ),
    );
    job.cancel();
    await expectLater(job.result, throwsA(isA<GenerationCancelled>()));
  });
}
