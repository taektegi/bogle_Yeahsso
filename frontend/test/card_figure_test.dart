import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/data/starter_friends.dart';
import 'package:bogle_app/src/models/character_friend.dart';
import 'package:bogle_app/src/screens/archive_screen.dart';
import 'package:bogle_app/src/theme/bogle_theme.dart';
import 'package:bogle_app/src/screens/house/house_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A clear 200 × 200 picture: a round body and, unless [tail] is false, a
/// long thin tail off to the right — the box's middle is right of the
/// body's.
Future<String> catWithTail({bool tail = true, bool ground = false}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  if (ground) {
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 200, 200),
      Paint()..color = const Color(0xFFFFF4D6),
    );
  }
  canvas.drawCircle(
    const Offset(70, 120),
    55,
    Paint()..color = const Color(0xFFF7BC8E),
  );
  if (tail) {
    canvas.drawRect(
      const Rect.fromLTWH(120, 110, 75, 8),
      Paint()..color = const Color(0xFFF3A976),
    );
  }
  final image = await recorder.endRecording().toImage(200, 200);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  final dir = await Directory.systemTemp.createTemp('bogle_card');
  final path = '${dir.path}/friend-$tail-$ground.png';
  await File(path).writeAsBytes(png!.buffer.asUint8List());
  return path;
}

const slot = Size(262, 312);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a tail is left out when weighing where the body is', () async {
    final look = (await artLookOf(await catWithTail()))!;
    final bodyX = look.body.dx;
    final boxX = look.drawn.center.dx;
    // The body (x 15–125 of 200 before the picture is cut to its figure)
    // is well left of the drawing's middle, which the tail pulls right.
    expect(bodyX, lessThan(boxX - .1));
  });

  test('on a card the body moves to the middle as far as it can, every '
      'pixel inside', () async {
    final look = (await artLookOf(await catWithTail()))!;
    final r = cardFigureRect(slot, look);
    final drawn = Rect.fromLTRB(
      r.left + look.drawn.left * r.width,
      r.top + look.drawn.top * r.height,
      r.left + look.drawn.right * r.width,
      r.top + look.drawn.bottom * r.height,
    );
    expect(drawn.left, greaterThanOrEqualTo(-.5));
    expect(drawn.right, lessThanOrEqualTo(slot.width + .5));
    expect(drawn.top, greaterThanOrEqualTo(-.5));
    expect(drawn.bottom, lessThanOrEqualTo(slot.height + .5));
    // Nearer the middle than centring the drawing's box would put it:
    // in the middle, or as far as the tail lets it go.
    final bodyX = r.left + look.body.dx * r.width;
    final boxCentred =
        slot.width / 2 + (look.body.dx - look.drawn.center.dx) * r.width;
    expect(
      (bodyX - slot.width / 2).abs(),
      lessThan((boxCentred - slot.width / 2).abs() - 5),
    );
    expect(
      (bodyX - slot.width / 2).abs() < 1 ||
          (drawn.right - slot.width).abs() < .5,
      isTrue,
    );
  });

  test('a plump friend is not blown up to fill the card', () async {
    final look = (await artLookOf(await catWithTail(tail: false)))!;
    final r = cardFigureRect(slot, look);
    final fits = math.min(
      slot.width / look.drawn.width,
      slot.height * look.natural.aspectRatio / look.drawn.height,
    );
    expect(r.width, lessThan(fits * .8));
    // A touch below the middle.
    final middle = r.top + look.drawn.center.dy * r.height;
    expect(middle, closeTo(slot.height * cardFigureMiddle, 1));
  });

  test('a picture with its own ground is fitted whole and centred', () async {
    final look = (await artLookOf(await catWithTail(ground: true)))!;
    expect(look.clearGround, isFalse);
    final r = cardFigureRect(slot, look);
    expect(r.width, closeTo(slot.width, .5));
    expect(r.center.dx, closeTo(slot.width / 2, .5));
    expect(r.center.dy, closeTo(slot.height / 2, .5));
  });

  test('뭉글이 keeps the size its card was designed with', () async {
    final look = (await artLookOf('assets/figma/character_card.svg'))!;
    final r = cardFigureRect(slot, look);
    final aspect = look.natural.aspectRatio;
    final before = math.min(slot.width, slot.height * aspect);
    expect(r.width / before, closeTo(1, .03));
  });

  Widget card(String art, Key key) => Directionality(
    textDirection: TextDirection.ltr,
    child: Center(
      child: SizedBox.fromSize(
        size: slot,
        child: CardFigure(
          assetPath: art,
          child: SizedBox.expand(key: key),
        ),
      ),
    ),
  );

  testWidgets('until its artwork is measured the friend waits, unseen', (
    tester,
  ) async {
    // Never measured before: its first frame can't know where it goes.
    final art = await tester.runAsync(() => catWithTail(ground: true));
    await tester.pumpWidget(card('$art?first', const ValueKey('a')));
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 0);
  });

  testWidgets('the artwork gets exactly its box, so a hero leaves from the '
      'drawing', (tester) async {
    // Measured ahead, as the archive does for every friend.
    final art = (await tester.runAsync(() => catWithTail()))!;
    final look = (await tester.runAsync(() => artLookOf(art)))!;
    const key = ValueKey('artwork');
    await tester.pumpWidget(card(art, key));
    // The measurement was made outside the test's clock: let it report.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    final expected = cardFigureRect(slot, look);
    final slotAt = tester.getTopLeft(find.byType(CardFigure));
    final box = tester.getRect(find.byKey(key));
    expect(box.left - slotAt.dx, closeTo(expected.left, .01));
    expect(box.top - slotAt.dy, closeTo(expected.top, .01));
    expect(box.width, closeTo(expected.width, .01));
    expect(box.height, closeTo(expected.height, .01));
  });

  group('card colour', () {
    /// A clear 200 × 200 picture painted in [colours], side by side.
    Future<String> painted(List<Color> colours) async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final width = 140 / colours.length;
      for (final (i, c) in colours.indexed) {
        canvas.drawRect(
          Rect.fromLTWH(30 + i * width, 30, width, 140),
          Paint()..color = c,
        );
      }
      final image = await recorder.endRecording().toImage(200, 200);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = await Directory.systemTemp.createTemp('bogle_colour');
      final path = '${dir.path}/friend.png';
      await File(path).writeAsBytes(png!.buffer.asUint8List());
      return path;
    }

    double contrast(Color a, Color b) {
      final la = a.computeLuminance(), lb = b.computeLuminance();
      return (math.max(la, lb) + .05) / (math.min(la, lb) + .05);
    }

    test('the friends the app ships with keep their colours', () async {
      for (final f in await InMemoryCharacterRepository().fetchFriends()) {
        final look = await artLookOf(f.assetPath);
        expect(friendCardColor(f, look), Color(f.accentHex), reason: f.name);
      }
    });

    test('a one-colour friend on its own colour gets a lighter shade of '
        'it, still readable', () async {
      const pink = Color(0xFFF299AF); // 무늬: its colour is its average
      final look = (await artLookOf(await painted([pink])))!;
      final card = cardColorFor(pink, look);
      expect(card, isNot(pink));
      expect(card.computeLuminance(), greaterThan(pink.computeLuminance()));
      final hue = HSLColor.fromColor(card).hue - HSLColor.fromColor(pink).hue;
      expect(hue.abs(), lessThan(12), reason: 'the same colour, lighter');
      expect(contrast(card, const Color(0xFF333333)), greaterThan(4.5));
    });

    test('a white friend gets a deeper card that still reads', () async {
      const white = Color(0xFFF5E9E5); // 보리
      final look = (await artLookOf(await painted([const Color(0xFFF8F2EE)])))!;
      final card = cardColorFor(white, look);
      expect(card.computeLuminance(), lessThan(white.computeLuminance() - .2));
      expect(contrast(card, const Color(0xFF333333)), greaterThan(4.5));
    });

    test('a friend that already stands out keeps its colour', () async {
      // 뽀야: blue and white, its average a grey lavender between them.
      const average = Color(0xFFBFBFD5);
      final look = (await artLookOf(
        await painted([const Color(0xFF6E7FC4), const Color(0xFFFFFBF2)]),
      ))!;
      expect(cardColorFor(average, look), average);
    });

    test('art with a ground of its own keeps the friend\'s colour', () async {
      final look = (await artLookOf(await catWithTail(ground: true)))!;
      const peach = Color(0xFFFFF4D6);
      expect(cardColorFor(peach, look), peach);
    });

    testWidgets('the archive card is painted in it', (tester) async {
      const pink = Color(0xFFF299AF);
      final art = (await tester.runAsync(() => painted([pink])))!;
      final look = await tester.runAsync(() => artLookOf(art));
      final friend = CharacterFriend(
        id: 'pink',
        name: '무늬',
        personality: '엉뚱한 상상가예요',
        favoriteThings: const ['바다'],
        speechStyle: '~지요!',
        assetPath: art,
        accentHex: pink.toARGB32(),
      );
      tester.view.physicalSize = const Size(1366, 1024);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildBogleTheme(),
          home: ArchiveScreen(
            repository: InMemoryCharacterRepository(friends: [friend]),
          ),
        ),
      );
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump(const Duration(milliseconds: 300));
      }
      final expected = cardColorFor(pink, look);
      final painted_ = tester
          .widgetList<ColoredBox>(find.byType(ColoredBox))
          .map((c) => c.color)
          .toSet();
      expect(painted_, contains(expected));
      expect(painted_, isNot(contains(pink)));
    });

    testWidgets('a card keeps its own colour while the cards are turned', (
      tester,
    ) async {
      final friends = starterFriends();
      tester.view.physicalSize = const Size(1366, 1024);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildBogleTheme(),
          home: ArchiveScreen(
            repository: InMemoryCharacterRepository(friends: friends),
          ),
        ),
      );
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump(const Duration(milliseconds: 300));
      }
      final cards = {
        for (final f in friends)
          friendCardColor(f, measuredArtLook(f.assetPath)),
      };
      Set<Color> painted() => tester
          .widgetList<ColoredBox>(
            find.descendant(
              of: find.byKey(const ValueKey('archive-carousel')),
              matching: find.byType(ColoredBox),
            ),
          )
          .map((c) => c.color)
          .toSet();
      final still = painted();
      // Past the middle the next card becomes the selected one; neither it
      // nor any other card washes over from a neighbour's colour.
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('archive-carousel'))),
      );
      for (var step = 0; step < 12; step++) {
        await gesture.moveBy(const Offset(-40, 0));
        await tester.pump(const Duration(milliseconds: 16));
        expect(painted().difference({...cards, ...still}), isEmpty);
      }
      await gesture.up();
      for (var f = 0; f < 30; f++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(painted().difference({...cards, ...still}), isEmpty);
      }
    });
  });
}
