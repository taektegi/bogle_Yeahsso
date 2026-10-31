import 'dart:math' as math;

import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/data/friend_talk.dart';
import 'package:bogle_app/src/data/window_view.dart';
import 'package:bogle_app/src/models/character_friend.dart';
import 'package:bogle_app/src/models/friend_status.dart';
import 'package:bogle_app/src/screens/archive_screen.dart';
import 'package:bogle_app/src/screens/friend_screen.dart';
import 'package:bogle_app/src/screens/house/chat_panel.dart';
import 'package:bogle_app/src/screens/house/figure_motion.dart';
import 'package:bogle_app/src/screens/house/house_widgets.dart';
import 'package:bogle_app/src/screens/house/room_scene.dart';
import 'package:bogle_app/src/screens/house/snacks.dart';
import 'package:bogle_app/src/theme/bogle_theme.dart';
import 'package:bogle_app/src/widgets/bogle_widgets.dart';
import 'package:bogle_app/src/widgets/top_bar.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/top_bar_expect.dart';

Future<void> show(
  WidgetTester tester,
  Widget home, {
  Size size = const Size(1366, 1024),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildBogleTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: home,
    ),
  );
  await tester.pumpAndSettle();
}

Future<CharacterFriend> firstFriend(CharacterRepository repo) async =>
    (await repo.fetchFriends()).first;

/// Early afternoon: every friend is up (bedtime is 9 pm to 7 am).
DateTime afternoon() => DateTime(2026, 9, 28, 14);

String bubble(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const ValueKey('house-bubble')))
    .data!
    .replaceAll('\u2060', '');

void main() {
  // Every friend's drawing is read before any test runs, on the real clock:
  // decoding images can't finish inside a test's fake one.
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final f in await InMemoryCharacterRepository().fetchFriends()) {
      await anchorsFor(f.assetPath);
    }
  });

  testWidgets('a long name stays on one line in the name card', (tester) async {
    final repository = InMemoryCharacterRepository();
    final friend = (await firstFriend(
      repository,
    )).copyWith(name: '우리의 아주아주 사랑스럽고 소중한 무지개 친구');
    await show(
      tester,
      FriendScreen(repository: repository, friend: friend, clock: afternoon),
      size: const Size(1024, 768),
    );
    final name = find.descendant(
      of: find.byType(NamePlate),
      matching: find.text(friend.name),
    );
    expect(tester.widget<Text>(name).maxLines, 1);
    expect(tester.widget<Text>(name).overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final size in const [
    Size(1024, 768),
    Size(1194, 834),
    Size(1366, 1024),
  ]) {
    testWidgets('the house follows Figma 568:2335 at $size', (tester) async {
      final repository = InMemoryCharacterRepository();
      final friends = await repository.fetchFriends();
      await show(
        tester,
        FriendScreen(
          repository: repository,
          friend: friends.first,
          clock: afternoon,
        ),
        size: size,
      );
      // The shared top bar with a "Home" pill, the round back button below
      // the wordmark and the name card below that.
      expectTopBar(tester, pill: 'Home');
      final logo = tester.getRect(find.byKey(const ValueKey('top-bar-logo')));
      final back = tester.getRect(find.byType(BogleBackButton));
      final card = tester.getRect(find.byType(NamePlate));
      expect(back.top, greaterThan(logo.bottom));
      expect(back.center.dx, closeTo(logo.left + 59 - 48 + 34, 30));
      expect(card.top, greaterThan(back.bottom));
      expect(find.text('활발하고 호기심이 많아요'), findsOneWidget);
      expect(find.text('오늘도 힘찬 하루 !'), findsOneWidget);
      // Three cream tiles in a row along the bottom, centred.
      final tiles = [
        for (final label in ['대화하기', '간식주기', '초대하기'])
          tester.getRect(find.bySemanticsLabel(label)),
      ];
      for (final t in tiles) {
        expect(t.top, closeTo(tiles.first.top, .01));
      }
      expect(
        (tiles.first.left + tiles.last.right) / 2,
        closeTo(size.width / 2, 1),
      );
      expect(tiles.last.bottom, lessThan(size.height));
      // Not in the design: the status card, the doll button, the side
      // arrows and the level.
      expect(find.text('오늘의 상태'), findsNothing);
      expect(find.text('인형 만들기'), findsNothing);
      expect(find.byTooltip('다음 친구의 집'), findsNothing);
      expect(find.textContaining('Lv.'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('the window shows the friend\'s own view, at night its night '
      'picture, and the lights go out at bedtime', (tester) async {
    final repo = InMemoryCharacterRepository();
    const view = WindowView(
      day: 'assets/figma/house_view_aquarium_day.png',
      night: 'assets/figma/house_view_aquarium_night.png',
    );
    final friend = (await firstFriend(repo)).copyWith(view: view);
    var now = afternoon();
    await show(
      tester,
      FriendScreen(repository: repo, friend: friend, clock: () => now),
    );
    Iterable<String> pictures() => find
        .descendant(of: find.byType(RoomScene), matching: find.byType(Image))
        .evaluate()
        .map((e) => ((e.widget as Image).image as AssetImage).assetName);
    expect(pictures(), contains(view.day));
    expect(pictures(), isNot(contains(view.night)));
    now = DateTime(2026, 9, 28, 23);
    await tester.pump(const Duration(minutes: 1, seconds: 2));
    await tester.pumpAndSettle();
    expect(pictures(), contains(view.night));
    expect(find.text('지금은 자는 중...'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('a window view is asked for from what the child chose', () async {
    final friends = await InMemoryCharacterRepository().fetchFriends();
    final munguri = friends.first;
    final day = WindowViewPrompt.day(munguri);
    final night = WindowViewPrompt.night(munguri);
    // 뭉글이 lives in the sea and loves apples and clouds.
    expect(day.prompt, contains('under the sea'));
    expect(day.prompt, contains('apple'));
    expect(day.prompt, contains('clouds'));
    expect(day.prompt, contains('bright, playful'));
    expect(day.prompt, contains('#8BA2FF'));
    expect(day.prompt, isNot(contains(munguri.name)));
    expect(day.negativePrompt, contains('window frame'));
    expect(day.negativePrompt, contains('text'));
    expect(night.night, isTrue);
    expect(night.prompt, contains('night'));
    expect(day.size.width / day.size.height, closeTo(WindowPane.aspect, .1));
    // Something unknown goes in as the child wrote it.
    expect(WindowViewPrompt.propOf('무지개 사탕'), contains('무지개 사탕'));
    expect(
      WindowViewPrompt.placeOf(friends[1]),
      contains('forest'),
    ); // 뚜치: 숲속, 도토리
  });

  test('status drifts gently while away and never below the floor', () {
    final start = DateTime(2026, 9, 26, 9);
    final aged = FriendStatus(
      fullness: 30,
      mood: 30,
      energy: 30,
      updatedAt: start,
    ).aged(start.add(const Duration(days: 2)));
    expect(aged.fullness, FriendStatus.floor);
    expect(aged.mood, FriendStatus.floor);
    final rested = FriendStatus(
      energy: 20,
      asleep: true,
      updatedAt: start,
    ).aged(start.add(const Duration(hours: 4)));
    expect(rested.energy, greaterThan(70));
  });

  CharacterFriend withStyle(String style) => CharacterFriend(
    id: 'x',
    name: '뭉글이',
    personality: '',
    favoriteThings: const ['사과'],
    speechStyle: style,
    assetPath: 'a.svg',
    accentHex: 0,
  );

  List<String> everyLine(String style) {
    final talk = FriendTalk(withStyle(style), random: math.Random(1));
    return [
      for (final topic in TalkTopic.values)
        for (var i = 0; i < 12; i++) talk.say(topic),
    ];
  }

  test('~지요 lines are conjugated, never glued on (no 기뻐지요)', () {
    final lines = everyLine('~지요!');
    expect(FriendTalk(withStyle('~지요!')).register, Register.jiyo);
    for (final line in lines) {
      expect(line, isNot(matches(RegExp(r'(어|아|워|뻐|해|줘)지요'))), reason: line);
      expect(line, isNot(contains('{f}')));
    }
    final talk = FriendTalk(withStyle('~지요!'), random: math.Random(1));
    expect(talk.say(TalkTopic.snack), endsWith('지요!'));
  });

  test('해요체 is polite and 반말 stays casual', () {
    for (final line in everyLine('해요체')) {
      if (line.contains('쿨쿨') || line.startsWith('음냐')) continue;
      expect(line, matches(RegExp(r'(요|세요)[!?]$')), reason: line);
    }
    for (final line in everyLine('반말')) {
      expect(line, isNot(matches(RegExp(r'지요[!?]$'))), reason: line);
    }
    expect(everyLine('느긋하게').where((l) => l.endsWith('~')), isNotEmpty);
    final talk = FriendTalk(withStyle('반말'));
    expect(talk.topicFor('나랑 놀자'), TalkTopic.play);
    expect(talk.topicFor('사랑해'), TalkTopic.love);
  });

  testWidgets('archive carousel moves between friends and opens a house', (
    tester,
  ) async {
    await show(
      tester,
      ArchiveScreen(repository: InMemoryCharacterRepository()),
    );
    expect(find.textContaining('각자의 집에서'), findsNothing);
    expect(find.text('뭉글이의 집에 놀러 가기'), findsOneWidget);
    // Figma 243:1612: 268 × 468 cards with two cream circles behind the
    // name, the circles 145 pt wide on a 268 pt card.
    final card = tester.getRect(
      find.byKey(const ValueKey('archive-selected-card')),
    );
    expect(card.width / card.height, closeTo(268 / 468, .01));
    final circles = find.descendant(
      of: find.byKey(const ValueKey('archive-selected-card')),
      matching: find.byKey(const ValueKey('archive-card-circles')),
    );
    expect(tester.getSize(circles).width, closeTo(card.width * 145 / 268, .5));
    // Every card's name, introduction and drawing are centred on the card,
    // however short its introduction (네모린's leaned left). The carousel
    // builds the cards near the middle, so it steps through them all and
    // comes round to 뭉글이 again.
    final friends = await InMemoryCharacterRepository().fetchFriends();
    for (final (i, friend) in friends.indexed) {
      final selected = find.byKey(const ValueKey('archive-selected-card'));
      final name = find.descendant(
        of: selected,
        matching: find.text(friend.name),
      );
      final box = tester.getRect(
        find.ancestor(of: name, matching: find.byType(ColoredBox)).first,
      );
      for (final part in [
        name,
        find.descendant(
          of: selected,
          matching: find.text(friend.displayIntroduction),
        ),
      ]) {
        expect(
          tester.getCenter(part).dx,
          closeTo(box.center.dx, 1),
          reason: friend.name,
        );
      }
      final next = friends[(i + 1) % friends.length];
      await tester.tap(find.bySemanticsLabel(RegExp('^${next.name},')));
      await tester.pumpAndSettle();
      expect(find.text('${next.name}의 집에 놀러 가기'), findsOneWidget);
    }
    await tester.tap(find.bySemanticsLabel(RegExp('^뚜치,')));
    await tester.pumpAndSettle();
    expect(find.text('뚜치의 집에 놀러 가기'), findsOneWidget);
    await tester.tap(find.text('뚜치의 집에 놀러 가기'));
    await tester.pumpAndSettle();
    expect(find.byType(FriendScreen), findsOneWidget);
    expect(
      find.descendant(of: find.byType(NamePlate), matching: find.text('뚜치')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the card opens into the house; the friend lands, then talks', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1194, 834);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildBogleTheme(),
        home: ArchiveScreen(repository: InMemoryCharacterRepository()),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final card = find
        .byKey(const ValueKey('archive-selected-card'))
        .evaluate()
        .single;
    await tester.tap(find.byKey(const ValueKey('archive-selected-card')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // Mid-way: the friend is in flight from its card and keeps quiet.
    expect(find.byType(FriendScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('house-bubble')), findsNothing);
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // Landed: now it says hello.
    expect(find.byKey(const ValueKey('house-bubble')), findsWidgets);
    // Back: the house folds into the card again, the friend gliding home
    // like the startup wordmark: steadily down into its card, never popping
    // back up, and ending exactly on the card's drawing.
    await tester.tap(find.byTooltip('뒤로'));
    await tester.pump();
    final flight = find.byKey(const ValueKey('friend-in-flight'));
    final path = <Rect>[];
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (flight.evaluate().isNotEmpty) path.add(tester.getRect(flight));
    }
    expect(path.length, greaterThan(8));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final cardArt = tester.getRect(
      find.descendant(
        of: find.byKey(const ValueKey('archive-selected-card')),
        matching: find.byType(FriendArtwork),
      ),
    );
    // Ever closer to the card, never wobbling back; ending on its drawing.
    for (var i = 1; i < path.length; i++) {
      expect(
        (path[i].center - cardArt.center).distance,
        lessThanOrEqualTo((path[i - 1].center - cardArt.center).distance + .5),
        reason: 'frame $i',
      );
    }
    expect((path.last.center - cardArt.center).distance, lessThan(12));
    expect(find.byType(FriendScreen), findsNothing);
    // The same card it left from: the carousel isn't rebuilt under it, so
    // nothing jumps as the friend lands back.
    expect(
      find.byKey(const ValueKey('archive-selected-card')).evaluate().single,
      same(card),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('house hero hands off a neutral pose before life eases in', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1194, 834);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = InMemoryCharacterRepository();
    final friend = (await firstFriend(
      repository,
    )).copyWith(sleep: const SleepSchedule(bedtime: 0, wakeTime: 0));
    await repository.saveFriend(friend);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildBogleTheme(),
        home: ArchiveScreen(repository: repository),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byKey(const ValueKey('archive-selected-card')));
    await tester.pump();
    FigurePose pose() =>
        (tester.state(find.byType(LivingCharacter)) as dynamic).debugPose
            as FigurePose;
    Size? flightLayout;
    Element? flightElement;
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(pose().scaleY, 1, reason: 'no hidden breathing during flight');
      expect(pose().armLeft, 0, reason: 'no hidden sway during flight');
      final artwork = find.byKey(const ValueKey('friend-in-flight'));
      flightLayout ??= tester.getSize(artwork);
      flightElement ??= artwork.evaluate().single;
      expect(tester.getSize(artwork), flightLayout);
      expect(artwork.evaluate().single, same(flightElement));
    }
    final landingFigure = find
        .byType(FriendFigure, skipOffstage: false)
        .evaluate()
        .single;
    final flightBox = tester.renderObject<RenderBox>(
      find.byKey(const ValueKey('friend-in-flight')),
    );
    final flight = MatrixUtils.transformRect(
      flightBox.getTransformTo(null),
      Offset.zero & flightBox.size,
    );
    await tester.pump(const Duration(milliseconds: 40));
    // Hero completion is removed on the following frame; sample through
    // that handoff too instead of skipping it with pumpAndSettle.
    for (var i = 0; i < 3; i++) {
      if (find.byType(FriendFigure).evaluate().isNotEmpty) break;
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(pose().scaleY, closeTo(1, .001));
    expect(pose().armLeft, closeTo(0, .001));
    final landed = tester.getRect(
      find.descendant(
        of: find.byType(LivingCharacter),
        matching: find.byType(FriendFigure),
      ),
    );
    expect(find.byType(FriendFigure).evaluate().single, same(landingFigure));
    expect((flight.center - landed.center).distance, lessThan(.5));
    expect(flight.width, closeTo(landed.width, .5));
    for (var i = 0; i < 20; i++) {
      final before = pose();
      await tester.pump(const Duration(milliseconds: 16));
      expect((pose().scaleY - before.scaleY).abs(), lessThan(.003));
      expect((pose().armLeft - before.armLeft).abs(), lessThan(.008));
    }
    expect(pose().scaleY, isNot(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a chosen snack waits for the tray to tuck away', (tester) async {
    final repo = InMemoryCharacterRepository();
    final friend = await firstFriend(repo);
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildBogleTheme(),
        home: FriendScreen(repository: repo, friend: friend, clock: afternoon),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.text('간식주기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.bySemanticsLabel(RegExp('^쿠키 주기')));
    await tester.pump();
    // Sliding away: the snack is not handed over until the tray is gone.
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byType(Eating), findsNothing);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('snack-tray')), findsNothing);
    expect(find.byType(Eating), findsOneWidget);
    // Eating takes its time: "아~", three chomps, chewing, a gulp.
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(Eating), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1200));
    expect(find.byType(Eating), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('every snack is eaten, however full the friend is', (
    tester,
  ) async {
    final repo = InMemoryCharacterRepository();
    final friend = await firstFriend(repo);
    await repo.saveStatus(
      friend.id,
      FriendStatus(fullness: 40, energy: 25, updatedAt: DateTime.now()),
    );
    await show(
      tester,
      FriendScreen(
        repository: repo,
        friend: friend,
        random: math.Random(2),
        clock: afternoon,
      ),
    );
    // Snacks come from a tray; the friend takes two bites and it's gone.
    await tester.tap(find.bySemanticsLabel('간식주기'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('쿠키 주기'));
    // The tray goes away so nothing covers the snack being eaten.
    await tester.pump();
    expect(find.bySemanticsLabel('쿠키 주기'), findsNothing);
    expect(find.byType(Eating), findsOneWidget);
    await tester.pumpAndSettle();
    expect((await repo.fetchStatus(friend.id)).fullness, 62);

    // 뭉글이 loves apples: dragging one onto it is a treat.
    await tester.tap(find.bySemanticsLabel('간식주기'));
    await tester.pumpAndSettle();
    final apple = find.bySemanticsLabel(RegExp('^사과 주기'));
    final to = tester.getCenter(find.bySemanticsLabel('뭉글이 쓰다듬기'));
    final drag = await tester.startGesture(tester.getCenter(apple));
    await tester.pump(const Duration(milliseconds: 100));
    await drag.moveTo(to);
    await tester.pump();
    await drag.up();
    await tester.pumpAndSettle();
    final treated = await repo.fetchStatus(friend.id);
    expect(treated.fullness, 84);
    expect(bubble(tester), contains('사과'));

    // There is no "full": at 100 it still eats every snack it's given.
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.bySemanticsLabel('간식주기'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('쿠키 주기'));
      await tester.pump();
      expect(find.byType(Eating), findsOneWidget, reason: 'snack $i');
      await tester.pumpAndSettle();
      expect(bubble(tester), isNot(anyOf(contains('배불러'), contains('빵빵'))));
    }
    expect((await repo.fetchStatus(friend.id)).fullness, 100);

    // There is no bubble game and no bedtime button any more.
    expect(find.bySemanticsLabel('놀아 주기'), findsNothing);
    expect(find.bySemanticsLabel('재우기'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a snack given mid-bite is eaten next', (tester) async {
    final repo = InMemoryCharacterRepository();
    final friend = await firstFriend(repo);
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildBogleTheme(),
        home: FriendScreen(repository: repo, friend: friend, clock: afternoon),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    final before = (await repo.fetchStatus(friend.id)).mood;
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text('간식주기'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.bySemanticsLabel(RegExp('^쿠키 주기')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }
    // The first is being eaten; the second waits, then is eaten too.
    expect(find.byType(Eating), findsOneWidget);
    var eaten = 0;
    Snack? last;
    for (var i = 0; i < 120 && eaten < 2; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      final now = find.byType(Eating).evaluate().isEmpty
          ? null
          : (find.byType(Eating).evaluate().first.widget as Eating).snack;
      if (last != null && !identical(now, last)) eaten++;
      last = now;
    }
    expect(eaten, 2);
    expect(
      (await repo.fetchStatus(friend.id)).mood,
      greaterThanOrEqualTo(math.min(100, before + 10)),
    );
    await tester.pumpWidget(const SizedBox());
  });

  test('the house balloon is Figma 576:2848\'s one shape', () {
    // Figma: M238 0 … V133 … H39.99 L0 174.99 V2 … — a 240 × 135 box whose
    // left edge runs on to the tail's point; the tail is 40 × 40.
    final balloon = SpeechBubble.boxyOutline(const Size(240, 175));
    expect(balloon.getBounds(), const Rect.fromLTWH(0, 0, 240, 175));
    for (final inside in const [
      Offset(1, 134), // the box's bottom-left: no notch, it runs straight on
      Offset(1, 172), // just above the point
      Offset(38, 136), // under the box, by the tail's top right
      Offset(238, 133), // the rounded bottom-right corner, inside it
    ]) {
      expect(balloon.contains(inside), isTrue, reason: '$inside');
    }
    for (final outside in const [
      Offset(42, 137), // past the tail's top right
      Offset(20, 170), // beside the diagonal edge
      Offset(239.8, 134.8), // outside the rounded corner
    ]) {
      expect(balloon.contains(outside), isFalse, reason: '$outside');
    }
    // Flipped, the point is under the right edge.
    final flipped = SpeechBubble.boxyOutline(
      const Size(240, 175),
      tailRight: true,
    );
    expect(flipped.contains(const Offset(239, 172)), isTrue);
    expect(flipped.contains(const Offset(1, 172)), isFalse);
  });

  testWidgets('a new line swaps balloons at the tail without a jump', (
    tester,
  ) async {
    final repo = InMemoryCharacterRepository();
    final friend = await firstFriend(repo);
    tester.view.physicalSize = const Size(1194, 834);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildBogleTheme(),
        home: FriendScreen(
          repository: repo,
          friend: friend,
          random: math.Random(4),
          clock: afternoon,
        ),
      ),
    );
    final balloons = find.byType(SpeechBubble);
    for (var i = 0; i < 40 && balloons.evaluate().length != 1; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(seconds: 1));
    final before = bubble(tester);
    final start = tester.getRect(balloons);
    await tester.tap(find.bySemanticsLabel('뭉글이 쓰다듬기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    // Mid-swap: both lines are there, sharing the tail's corner.
    expect(balloons, findsNWidgets(2));
    // Where each is laid out (each is drawn scaling about its own tail).
    final rects = [
      for (final e
          in find
              .ancestor(of: balloons, matching: find.byType(ScaleTransition))
              .evaluate())
        tester.getRect(find.byWidget(e.widget)),
    ];
    expect(rects, hasLength(2));
    expect(rects[0].bottomLeft, offsetMoreOrLessEquals(rects[1].bottomLeft));
    // The balloon glides: a frame in, it has not leapt more than part way.
    final midLeft = rects.map((r) => r.left).reduce(math.min);
    await tester.pump(const Duration(milliseconds: 400));
    expect(balloons, findsOneWidget);
    expect(bubble(tester), isNot(before));
    final end = tester.getRect(balloons);
    if ((end.left - start.left).abs() > 4) {
      expect(
        (midLeft - start.left).abs(),
        lessThan((end.left - start.left).abs()),
      );
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('chatting adds memories quietly; no level on the plate', (
    tester,
  ) async {
    final repo = InMemoryCharacterRepository();
    final friend = await firstFriend(repo); // Lv.4, 12 memories
    await show(
      tester,
      FriendScreen(
        repository: repo,
        friend: friend,
        random: math.Random(3),
        clock: afternoon,
      ),
    );
    expect(find.textContaining('Lv.'), findsNothing);
    expect(find.textContaining('추억'), findsNothing);
    await tester.tap(find.bySemanticsLabel('대화하기'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.widgetWithText(ActionChip, '사랑해!'));
      await tester.pump(const Duration(milliseconds: 500));
    }
    await tester.enterText(
      find.byKey(const ValueKey('house-chat-field')),
      '안녕',
    );
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump(const Duration(milliseconds: 500));
    final saved = (await repo.fetchFriends()).first;
    expect(saved.memories, 16);
    expect(saved.level, 5);
    await tester.tap(find.byKey(const ValueKey('house-chat-return')));
    await tester.pump(const Duration(seconds: 2));
    expect(find.textContaining('Lv.'), findsNothing);
    expect(bubble(tester), isNot(contains('레벨')));
  });

  for (final size in const [Size(1366, 1024), Size(1194, 834)]) {
    testWidgets('the open chat stands tall beside the friend and the tiles '
        'make way (${size.width.toInt()} wide)', (tester) async {
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 20);
      addTearDown(tester.view.resetPadding);
      final repo = InMemoryCharacterRepository();
      await show(
        tester,
        FriendScreen(
          repository: repo,
          friend: await firstFriend(repo),
          clock: afternoon,
        ),
        size: size,
      );
      await tester.tap(find.bySemanticsLabel('대화하기'));
      await tester.pumpAndSettle();
      final chat = tester.getRect(find.byKey(const ValueKey('chat')));
      final figure = tester.getRect(find.byKey(const ValueKey('house-figure')));
      // Beside the friend, not over it, and most of the screen tall.
      expect(figure.right, lessThan(chat.left));
      expect(figure.left, greaterThanOrEqualTo(0));
      expect(chat.height, greaterThan(size.height * .6));
      expect(chat.width, greaterThanOrEqualTo(440));
      expect(chat.bottom, lessThanOrEqualTo(size.height - 20));
      // Snacks and invites wait outside the conversation.
      for (final tile in ['대화하기', '간식주기', '초대하기']) {
        expect(find.text(tile), findsNothing, reason: tile);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('with the keyboard up both the scene and compact conversation '
      'and the whole chat stay above it', (tester) async {
    // An 11-inch iPad on its side, the smallest the app is laid out for.
    final repo = InMemoryCharacterRepository();
    await show(
      tester,
      FriendScreen(
        repository: repo,
        friend: await firstFriend(repo),
        clock: afternoon,
      ),
      size: const Size(1194, 834),
    );
    final figure = find.byKey(const ValueKey('house-figure'));
    final before = tester.getRect(figure);
    await tester.tap(find.bySemanticsLabel('대화하기'));
    await tester.pumpAndSettle();

    const keyboard = 400.0;
    tester.view.viewInsets = const FakeViewPadding(bottom: keyboard);
    addTearDown(tester.view.resetViewInsets);
    await tester.tap(find.byKey(const ValueKey('house-chat-field')));
    await tester.pumpAndSettle();

    const above = 834 - keyboard;
    final after = tester.getRect(figure);
    expect(after.width, lessThanOrEqualTo(before.width));
    expect(after.bottom, lessThanOrEqualTo(above));
    expect(after.top, greaterThanOrEqualTo(0));
    final chat = tester.getRect(find.byKey(const ValueKey('chat')));
    expect(chat.bottom, lessThanOrEqualTo(above));
    expect(chat.top, greaterThanOrEqualTo(0));
    expect(after.right, lessThan(chat.left));
    expect(tester.takeException(), isNull);

    // Writing its own line, the quick replies make way; the field keeps
    // what was typed and the keyboard stays for the next line.
    final field = find.byKey(const ValueKey('house-chat-field'));
    await tester.enterText(field, '안녕');
    await tester.pump();
    expect(find.widgetWithText(ActionChip, '오늘 뭐 했어?'), findsNothing);
    expect(tester.widget<TextField>(field).controller!.text, '안녕');
    await tester.tap(find.byTooltip('보내기'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.descendant(
        of: find.byType(ChatPanel),
        matching: find.byWidgetPredicate(
          (w) => w is Text && w.semanticsLabel == '안녕',
        ),
      ),
      findsOneWidget,
    );
    // The friend thinks in its balloon and in the chat card alike.
    expect(find.bySemanticsLabel('생각하는 중'), findsWidgets);
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
    await tester.pump(const Duration(seconds: 1));
    expect(find.bySemanticsLabel('생각하는 중'), findsNothing);
    expect(find.widgetWithText(ActionChip, '오늘 뭐 했어?'), findsOneWidget);

    // Put away, the house comes back down as it was.
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('house-chat-return')));
    await tester.pumpAndSettle();
    expect(tester.getRect(figure), before);
  });

  testWidgets('the friend acts out what it is told: play, today, likes', (
    tester,
  ) async {
    final repo = InMemoryCharacterRepository();
    final friend = await firstFriend(repo);
    await show(
      tester,
      FriendScreen(repository: repo, friend: friend, clock: afternoon),
    );
    await tester.tap(find.bySemanticsLabel('대화하기'));
    await tester.pumpAndSettle();
    Act? cue() => tester
        .widget<LivingCharacter>(find.byType(LivingCharacter).first)
        .cue
        ?.act;
    for (final (say, act) in const [
      ('같이 놀자!', Act.wonder),
      ('오늘 뭐 했어?', Act.wonder),
      ('뭘 좋아해?', Act.wonder),
    ]) {
      await tester.tap(find.widgetWithText(ActionChip, say));
      await tester.pump(const Duration(milliseconds: 600));
      expect(cue(), act, reason: say);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('near bedtime the friend is sleepy', (tester) async {
    final repo = InMemoryCharacterRepository();
    final friend = await firstFriend(repo);
    final bed = friend.sleep.bedtime;
    final evening = DateTime(
      2026,
      9,
      28,
      bed ~/ 60,
      bed % 60,
    ).subtract(const Duration(minutes: 30));
    await show(
      tester,
      FriendScreen(repository: repo, friend: friend, clock: () => evening),
    );
    final host = tester.widget<LivingCharacter>(
      find.byType(LivingCharacter).first,
    );
    expect(host.vibe, Vibe.sleepy);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a new friend moves in', (tester) async {
    final repo = InMemoryCharacterRepository();
    final friends = await repo.fetchFriends();
    await show(
      tester,
      FriendScreen(
        repository: repo,
        friend: friends.first,
        celebrate: true,
        clock: afternoon,
      ),
    );
    expect(find.text('친구가 되었어요!'), findsOneWidget);
    await tester.tap(find.text('집 구경하기'));
    await tester.pumpAndSettle();
    expect(find.text('친구가 되었어요!'), findsNothing);
    expect(find.byType(NamePlate), findsOneWidget);
  });

  testWidgets('back returns to the archive and home closes every page', (
    tester,
  ) async {
    final repo = InMemoryCharacterRepository();
    await show(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ArchiveScreen(repository: repo),
                ),
              ),
              child: const Text('start'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('뭉글이의 집에 놀러 가기'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('뒤로'));
    await tester.pumpAndSettle();
    expect(find.byType(FriendScreen), findsNothing);
    expect(find.byType(ArchiveScreen), findsOneWidget);

    await tester.tap(find.text('뭉글이의 집에 놀러 가기'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('top-action-홈')));
    await tester.pumpAndSettle();
    expect(find.byType(FriendScreen), findsNothing);
    expect(find.byType(ArchiveScreen), findsNothing);
  });

  test('bedtime runs past midnight; the next change is the next edge', () {
    const night = SleepSchedule(wakeTime: 7 * 60 + 30);
    expect(night.asleepAt(DateTime(2026, 9, 28, 20, 59)), isFalse);
    expect(night.asleepAt(DateTime(2026, 9, 28, 21)), isTrue);
    expect(night.asleepAt(DateTime(2026, 9, 29, 3)), isTrue);
    expect(night.asleepAt(DateTime(2026, 9, 29, 7, 29)), isTrue);
    expect(night.asleepAt(DateTime(2026, 9, 29, 7, 30)), isFalse);
    expect(
      night.nextChange(DateTime(2026, 9, 28, 14)),
      DateTime(2026, 9, 28, 21),
    );
    expect(
      night.nextChange(DateTime(2026, 9, 28, 23)),
      DateTime(2026, 9, 29, 7, 30),
    );
    const nap = SleepSchedule(bedtime: 13 * 60, wakeTime: 14 * 60);
    expect(nap.asleepAt(DateTime(2026, 9, 28, 13, 30)), isTrue);
    expect(nap.asleepAt(DateTime(2026, 9, 28, 15)), isFalse);
    expect(
      const SleepSchedule(
        bedtime: 600,
        wakeTime: 600,
      ).asleepAt(DateTime(2026, 9, 28, 10)),
      isFalse,
    );
    expect(timeOfDayLabel(21 * 60), '밤 9시');
    expect(timeOfDayLabel(7 * 60 + 30), '아침 7시 30분');
    expect(timeOfDayLabel(0), '새벽 12시');
    expect(timeOfDayLabel(12 * 60), '오후 12시');
  });

  testWidgets('at bedtime the friend falls asleep by itself, and wakes up', (
    tester,
  ) async {
    final repo = InMemoryCharacterRepository();
    final friend = await firstFriend(repo);
    var now = DateTime(2026, 9, 28, 20, 59);
    await show(
      tester,
      FriendScreen(
        repository: repo,
        friend: friend,
        random: math.Random(5),
        clock: () => now,
      ),
    );
    expect(find.text('밤 9시 ~ 아침 7시'), findsOneWidget);
    expect(find.text('지금은 자는 중...'), findsNothing);

    now = DateTime(2026, 9, 28, 21);
    await tester.pump(const Duration(minutes: 1, seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('지금은 자는 중...'), findsOneWidget);
    expect((await repo.fetchStatus(friend.id)).asleep, isTrue);
    // Asleep: no snacks or visitors, and a tap doesn't wake it.
    await tester.tap(find.bySemanticsLabel('간식주기'));
    await tester.tap(find.bySemanticsLabel('초대하기'));
    await tester.tap(find.bySemanticsLabel('뭉글이 쓰다듬기'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('snack-tray')), findsNothing);
    expect(find.byKey(const ValueKey('invite-tray')), findsNothing);
    expect(find.text('지금은 자는 중...'), findsOneWidget);

    now = DateTime(2026, 9, 29, 7);
    await tester.pump(const Duration(hours: 10));
    await tester.pumpAndSettle();
    expect(find.text('지금은 자는 중...'), findsNothing);
    expect(
      (await repo.fetchStatus(friend.id)).energy,
      greaterThanOrEqualTo(90),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a friend opened at night is already asleep', (tester) async {
    final repo = InMemoryCharacterRepository();
    final friend = await firstFriend(repo);
    await show(
      tester,
      FriendScreen(
        repository: repo,
        friend: friend,
        clock: () => DateTime(2026, 9, 28, 23, 30),
      ),
    );
    expect(find.text('지금은 자는 중...'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('bedtime can be changed from the name plate', (tester) async {
    final repo = InMemoryCharacterRepository();
    final friend = await firstFriend(repo);
    await show(
      tester,
      FriendScreen(repository: repo, friend: friend, clock: afternoon),
    );
    await tester.tap(find.byKey(const ValueKey('house-sleep-schedule')));
    await tester.pumpAndSettle();
    expect(find.text('뭉글이의 잠자는 시간'), findsOneWidget);
    // One hour later: two half-hour steps down the bedtime wheel.
    await tester.drag(
      find.descendant(
        of: find.byKey(const ValueKey('sleep-bedtime')),
        matching: find.byType(CupertinoPicker),
      ),
      const Offset(0, -72),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(find.text('밤 10시 ~ 아침 7시'), findsOneWidget);
    final saved = (await repo.fetchFriends()).first;
    expect(saved.sleep.bedtime, 22 * 60);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('invite a friend over, then see it off', (tester) async {
    final repo = InMemoryCharacterRepository();
    final friend = await firstFriend(repo);
    await show(
      tester,
      FriendScreen(
        repository: repo,
        friend: friend,
        random: math.Random(6),
        clock: afternoon,
      ),
    );
    await tester.tap(find.bySemanticsLabel('초대하기'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('invite-tray')), findsOneWidget);
    // Everyone but the host can come.
    expect(find.bySemanticsLabel('뭉글이 초대하기'), findsNothing);
    await tester.tap(find.bySemanticsLabel('뚜치 초대하기'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('invite-tray')), findsNothing);
    final guest = find.byKey(const ValueKey('house-guest'));
    expect(guest, findsOneWidget);
    expect(bubble(tester), contains('뚜치'));
    // The guest stands beside the host, both on the floor.
    final host = tester.getRect(find.bySemanticsLabel('뭉글이 쓰다듬기'));
    final visitor = tester.getRect(guest);
    expect(visitor.left, greaterThan(host.center.dx));
    expect(visitor.bottom, closeTo(host.bottom, 1));
    expect(visitor.right, lessThanOrEqualTo(1366));
    await tester.tap(find.bySemanticsLabel('뚜치 쓰다듬기'));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('배웅하기'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('house-guest')), findsNothing);
    expect(find.bySemanticsLabel('초대하기'), findsOneWidget);
    expect(bubble(tester), contains('뚜치'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the invite tile shows whose house it is; see-off, the guest', (
    tester,
  ) async {
    final repo = InMemoryCharacterRepository();
    final friends = await repo.fetchFriends();
    Finder silhouette(String asset) => find.descendant(
      of: find.bySemanticsLabel(RegExp('^(초대하기|배웅하기)\$')),
      matching: find.byKey(ValueKey('silhouette-$asset')),
    );
    for (final friend in friends) {
      await show(
        tester,
        FriendScreen(
          key: ValueKey(friend.id),
          repository: repo,
          friend: friend,
          clock: afternoon,
        ),
      );
      // The outline is read on the real clock.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      // 뭉글이's is Figma's own drawing (621:2129); the others are made
      // from their artwork.
      final asset = friend.name == '뭉글이'
          ? 'assets/figma/house_invite.svg'
          : friend.assetPath;
      expect(silhouette(asset), findsOneWidget, reason: friend.name);
    }
    // In 네모린's house, inviting 뚜치: the tile becomes 배웅하기 with 뚜치.
    await tester.tap(find.bySemanticsLabel('초대하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('뚜치 초대하기'));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    expect(silhouette('assets/figma/dduchi.png'), findsOneWidget);
    expect(silhouette('assets/figma/nemorin.png'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a guest hops in from off stage and lands beside the host', (
    tester,
  ) async {
    final repo = InMemoryCharacterRepository();
    final friend = await firstFriend(repo);
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildBogleTheme(),
        home: FriendScreen(
          repository: repo,
          friend: friend,
          random: math.Random(7),
          clock: afternoon,
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('초대하기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.bySemanticsLabel('네모린 초대하기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    final figure = find.descendant(
      of: find.byKey(const ValueKey('house-guest')),
      matching: find.byType(FriendFigure),
    );
    // Starts past the right edge of the room.
    expect(tester.getRect(figure).left, greaterThan(1366));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final spot = tester.getRect(find.byKey(const ValueKey('house-guest')));
    expect(
      tester.getRect(figure).center.dx,
      closeTo(spot.center.dx, spot.width * .12),
    );
    expect(bubble(tester), contains('네모린'));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('coming into a house, the friend waves hello', (tester) async {
    final repo = InMemoryCharacterRepository();
    final friend = await firstFriend(repo);
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildBogleTheme(),
        home: FriendScreen(
          repository: repo,
          friend: friend,
          random: math.Random(8),
          clock: afternoon,
        ),
      ),
    );
    await tester.pump();
    final host = tester.state(find.byType(LivingCharacter));
    double? raised() => (host as dynamic).debugPose.armRight as double?;
    // Not before the page has settled in...
    await tester.pump(const Duration(milliseconds: 300));
    expect(raised(), lessThan(.1));
    // ...then one arm goes up and waves.
    var highest = 0.0;
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 60));
      highest = math.max(highest, raised()!);
    }
    expect(highest, greaterThan(.3));
    await tester.pumpWidget(const SizedBox());
  });

  /// Lets what was read about the drawings reach the house (it arrives on
  /// the real clock).
  Future<void> settleFaces(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
  }

  testWidgets('in 네모린\'s house the snack goes to its mouth, not its body', (
    tester,
  ) async {
    final repo = InMemoryCharacterRepository();
    final friends = await repo.fetchFriends();
    final nemorin = friends.firstWhere((f) => f.name == '네모린');
    await show(
      tester,
      FriendScreen(repository: repo, friend: nemorin, clock: afternoon),
    );
    await settleFaces(tester);
    await tester.tap(find.bySemanticsLabel('간식주기'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('쿠키 주기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final figure = tester.getRect(
      find.descendant(
        of: find.bySemanticsLabel('네모린 쓰다듬기'),
        matching: find.byType(FriendFigure),
      ),
    );
    final snack = tester.getRect(find.byKey(const ValueKey('house-snack')));
    // The snout is at the top left of the giraffe; the snack is held in
    // front of it.
    expect(snack.center.dy, lessThan(figure.top + figure.height * .3));
    expect(snack.center.dx, lessThan(figure.left + figure.width * .15));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });

  for (final size in const [Size(1024, 768), Size(1366, 1024)]) {
    testWidgets(
      'every balloon stays on screen and clear of the cards at $size',
      (tester) async {
        final repo = InMemoryCharacterRepository();
        final friends = await repo.fetchFriends();
        for (final friend in friends) {
          await show(
            tester,
            FriendScreen(
              key: ValueKey(friend.id),
              repository: repo,
              friend: friend,
              clock: afternoon,
            ),
            size: size,
          );
          await settleFaces(tester);
          final balloon = tester.getRect(
            find
                .ancestor(
                  of: find.byKey(const ValueKey('house-bubble')),
                  matching: find.byType(SpeechBubble),
                )
                .first,
          );
          expect(balloon.left, greaterThanOrEqualTo(0), reason: friend.name);
          expect(
            balloon.right,
            lessThanOrEqualTo(size.width),
            reason: friend.name,
          );
          expect(
            balloon.top,
            greaterThan(
              tester.getRect(find.byKey(const ValueKey('top-bar-logo'))).bottom,
            ),
            reason: friend.name,
          );
          for (final card in [NamePlate, BogleBackButton]) {
            final r = tester.getRect(find.byType(card));
            expect(
              r.overlaps(balloon.deflate(6)),
              isFalse,
              reason: '${friend.name} $card',
            );
          }
          // It hangs over the friend's head, not off in a corner.
          final figure = tester.getRect(
            find.descendant(
              of: find.bySemanticsLabel('${friend.name} 쓰다듬기'),
              matching: find.byType(FriendFigure),
            ),
          );
          expect(
            balloon.bottom,
            lessThan(figure.center.dy),
            reason: friend.name,
          );
          expect(
            balloon.inflate(80).overlaps(figure),
            isTrue,
            reason: friend.name,
          );
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}

/// A chat balloon's text: they keep words whole with word joiners.
Finder chatLine(String text) => find.byWidgetPredicate(
  (w) => w is Text && w.data?.replaceAll('\u2060', '') == text,
);
