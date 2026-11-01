import 'dart:io';
import 'dart:ui' as ui;

import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/data/chat_service.dart';
import 'package:bogle_app/src/models/character_friend.dart';
import 'package:bogle_app/src/models/friend_status.dart';
import 'package:bogle_app/src/screens/friend_screen.dart';
import 'package:bogle_app/src/screens/house/chat_panel.dart';
import 'package:bogle_app/src/screens/house/house_widgets.dart';
import 'package:bogle_app/src/screens/house/scene_speech.dart';
import 'package:bogle_app/src/theme/bogle_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _canvas = ValueKey('house-details-canvas');

class _Reply implements ChatService {
  @override
  Future<String?> replyTo(CharacterFriend friend, String text) async =>
      '너랑 같이 구름을 구경하고 싶어. 우리 친구들과 함께 그림을 그리면 정말 재미있을 것 같아! 다음에는 네가 좋아하는 놀이도 알려 줘.';
  @override
  Future<List<ChatLine>> history(CharacterFriend friend) async => const [];
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await (FontLoader(
      'Yangjin',
    )..addFont(rootBundle.load('assets/fonts/Yangjin.ttf'))).load();
    await (FontLoader(
      'Pretendard',
    )..addFont(rootBundle.load('assets/fonts/Pretendard-Regular.otf'))).load();
    for (final f in await InMemoryCharacterRepository().fetchFriends()) {
      await anchorsFor(f.assetPath);
    }
  });

  Future<InMemoryCharacterRepository> open(
    WidgetTester tester, {
    Size size = const Size(1194, 834),
    bool reduced = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = InMemoryCharacterRepository();
    final friends = await repo.fetchFriends();
    for (final f in friends) {
      await repo.saveStatus(
        f.id,
        FriendStatus(fullness: 30, updatedAt: DateTime.now()),
      );
    }
    await tester.pumpWidget(
      RepaintBoundary(
        key: _canvas,
        child: MaterialApp(
          theme: buildBogleTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
            child: child!,
          ),
          home: FriendScreen(
            repository: repo,
            friend: friends.first,
            chat: _Reply(),
            clock: () => DateTime(2026, 10, 29, 14),
          ),
        ),
      ),
    );
    if (reduced) {
      await tester.pumpAndSettle();
    } else {
      for (var i = 0; i < 24; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }
    return repo;
  }

  Future<void> invite(WidgetTester tester) async {
    await tester.tap(find.bySemanticsLabel('초대하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('뚜치 초대하기'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('house-guest')), findsOneWidget);
  }

  Future<void> snack(WidgetTester tester, {String? recipient}) async {
    await tester.tap(find.bySemanticsLabel('간식주기'));
    await tester.pumpAndSettle();
    final cookie = find.bySemanticsLabel(RegExp('^쿠키 주기'));
    if (recipient == null) {
      await tester.tap(cookie);
    } else {
      final drag = await tester.startGesture(tester.getCenter(cookie));
      await tester.pump(const Duration(milliseconds: 100));
      await drag.moveTo(
        tester.getCenter(find.bySemanticsLabel('$recipient 쓰다듬기')),
      );
      await tester.pump();
      await drag.up();
    }
    await tester.pump();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (Platform.environment['BOGLE_HOUSE_SHOTS'] != '1') return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump();
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_canvas),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      await File(
        '/tmp/bogle-house-$name.png',
      ).writeAsBytes(png!.buffer.asUint8List());
    });
  }

  testWidgets('함께 서기·간식 공유·각자 돌봄 저장·배웅 후 중앙 복귀', (tester) async {
    final repo = await open(tester);
    final alone = tester.getRect(find.bySemanticsLabel('뭉글이 쓰다듬기'));
    await invite(tester);
    final host = tester.getRect(find.bySemanticsLabel('뭉글이 쓰다듬기'));
    final guest = tester.getRect(find.byKey(const ValueKey('house-guest')));
    expect(host.center.dx, lessThan(alone.center.dx));
    expect(guest.left, greaterThan(host.right));
    expect(guest.width / host.width, closeTo(.9, .01));
    expect(guest.bottom, closeTo(host.bottom, .1));
    await capture(tester, 'company');
    await snack(tester);
    await tester.pump(const Duration(milliseconds: 10));
    expect(find.byKey(const ValueKey('house-snack')), findsOneWidget);
    expect(find.byKey(const ValueKey('guest-snack')), findsOneWidget);
    await capture(tester, 'sharing');
    await tester.pumpAndSettle();
    expect((await repo.fetchStatus('mungle')).fullness, 52);
    expect((await repo.fetchStatus('dduchi')).fullness, 52);
    expect(await repo.fetchMemories('dduchi'), contains(contains('나눠 먹었어')));
    await tester.tap(find.bySemanticsLabel('배웅하기'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('house-guest')), findsNothing);
    expect(tester.getRect(find.bySemanticsLabel('뭉글이 쓰다듬기')), alone);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('끌어서 특정 친구에게 준 간식은 그 친구에게만 반영된다', (tester) async {
    final repo = await open(tester);
    await invite(tester);
    await snack(tester, recipient: '뚜치');
    await tester.pumpAndSettle();
    expect((await repo.fetchStatus('mungle')).fullness, 30);
    expect((await repo.fetchStatus('dduchi')).fullness, 52);
    await snack(tester, recipient: '뭉글이');
    await tester.pumpAndSettle();
    expect((await repo.fetchStatus('mungle')).fullness, 52);
    expect((await repo.fetchStatus('dduchi')).fullness, 52);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('이전에 예약한 친구 반응은 나중에 직접 터치한 동작을 덮지 않는다', (tester) async {
    await open(tester);
    await invite(tester);
    await tester.tap(find.bySemanticsLabel('뚜치 쓰다듬기'));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('뭉글이 쓰다듬기'));
    await tester.pump();
    final cue = tester
        .widget<LivingCharacter>(find.byType(LivingCharacter).first)
        .cue;
    await tester.pump(const Duration(milliseconds: 800));
    expect(
      tester.widget<LivingCharacter>(find.byType(LivingCharacter).first).cue,
      same(cue),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('먹는 중 배웅해도 주인의 식사만 끝나고 손님에게 유령 급여가 없다', (tester) async {
    final repo = await open(tester);
    await invite(tester);
    await snack(tester);
    await tester.pump(const Duration(milliseconds: 10));
    await tester.tap(find.bySemanticsLabel('배웅하기'));
    await tester.pumpAndSettle();
    expect((await repo.fetchStatus('mungle')).fullness, 52);
    expect((await repo.fetchStatus('dduchi')).fullness, 30);
    expect(find.byKey(const ValueKey('guest-snack')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  test('초대 대사 길이에 따라 읽는 시간과 답할 간격을 확보한다', () {
    expect(greetingReplyDelay('안녕!'), const Duration(milliseconds: 4650));
    expect(
      greetingReplyDelay('아' * 30),
      greaterThan(greetingReplyDelay('안녕!')),
    );
    expect(greetingReplyDelay('아' * 200), const Duration(milliseconds: 9150));
    expect(greetingReplyDelay('안 녕!'), greetingReplyDelay('안녕!'));
  });

  testWidgets('이름 표시는 없이 집주인의 인사를 읽은 뒤 손님이 답한다', (tester) async {
    await open(tester);
    await invite(tester);
    SceneSpeech speech() =>
        tester.widget<SceneSpeech>(find.byType(SceneSpeech));
    expect(speech().speaker, '뭉글이');
    final welcome = speech().text;
    final delay = greetingReplyDelay(welcome);
    void noNameHeading() {
      final bubble = find.byType(SpeechBubble);
      expect(tester.widget<SpeechBubble>(bubble).speaker, isNull);
      for (final name in ['뭉글이', '뚜치']) {
        expect(
          find.descendant(of: bubble, matching: find.text(name)),
          findsNothing,
        );
      }
    }

    noNameHeading();
    await capture(tester, 'welcome-no-name');
    final semantics = tester.ensureSemantics();
    expect(find.bySemanticsLabel('뭉글이의 말. $welcome'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(speech().text, welcome);
    await tester.pump(delay - const Duration(seconds: 2));
    expect(speech().speaker, '뭉글이');
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pumpAndSettle();
    expect(speech().speaker, '뚜치');
    expect(speech().text, isNot(welcome));
    noNameHeading();
    await capture(tester, 'visitor-no-name');
    expect(find.bySemanticsLabel('뚜치의 말. ${speech().text}'), findsOneWidget);
    semantics.dispose();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('인사 대기 중 쓰다듬으면 늦은 손님 인사가 새 반응을 덮지 않는다', (tester) async {
    await open(tester);
    await invite(tester);
    await tester.tap(find.bySemanticsLabel('뭉글이 쓰다듬기'));
    await tester.pumpAndSettle();
    final reply = tester.widget<SceneSpeech>(find.byType(SceneSpeech)).text;
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    final speech = tester.widget<SceneSpeech>(find.byType(SceneSpeech));
    expect(speech.speaker, '뭉글이');
    expect(speech.text, reply);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('카펫은 바닥에 고정된 채 부드럽게 넓어지고 배웅 후 복귀한다', (tester) async {
    await open(tester, reduced: false);
    Future<void> frames(int ms) async {
      for (var t = 0; t < ms; t += 50) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    final rug = find.byKey(const ValueKey('house-rug'));
    final alone = tester.getRect(rug);
    await tester.tap(find.bySemanticsLabel('초대하기'));
    await frames(400);
    await tester.tap(find.bySemanticsLabel('뚜치 초대하기'));
    await tester.pump();
    await tester.pump();
    var previous = tester.getRect(rug);
    for (var i = 0; i < 8; i++) {
      await frames(100);
      final current = tester.getRect(rug);
      expect(current.width, greaterThanOrEqualTo(previous.width));
      expect(current.width - previous.width, lessThan(45));
      expect(current.top, closeTo(alone.top, .01));
      expect(current.center.dx, closeTo(alone.center.dx, .01));
      previous = current;
    }
    expect(previous.width, closeTo(alone.width + 200, .01));
    expect(previous.height, closeTo(alone.height + 8, .01));
    await capture(tester, 'rug-expanded');
    await frames(3500);
    await tester.tap(find.bySemanticsLabel('배웅하기'));
    for (
      var i = 0;
      i < 160 &&
          find.byKey(const ValueKey('house-guest')).evaluate().isNotEmpty;
      i++
    ) {
      await frames(50);
    }
    expect(find.byKey(const ValueKey('house-guest')), findsNothing);
    previous = tester.getRect(rug);
    for (var i = 0; i < 8; i++) {
      await frames(100);
      final current = tester.getRect(rug);
      expect(current.width, lessThanOrEqualTo(previous.width));
      expect(previous.width - current.width, lessThan(45));
      expect(current.top, closeTo(alone.top, .01));
      previous = current;
    }
    expect(tester.getRect(rug), alone);
    expect(find.byKey(const ValueKey('house-guest')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final size in const [
    Size(1024, 768),
    Size(1194, 834),
    Size(1366, 1024),
  ]) {
    testWidgets('둘이 있는 대화와 키보드에서 두 친구·말풍선·대화창이 겹치지 않는다 $size', (tester) async {
      await open(tester, size: size);
      await invite(tester);
      await tester.tap(find.bySemanticsLabel('대화하기'));
      await tester.pumpAndSettle();
      await capture(tester, 'chat-${size.width.toInt()}');
      Rect panel() => tester.getRect(find.byKey(const ValueKey('chat')));
      for (final name in ['뭉글이', '뚜치']) {
        final character = tester.getRect(find.bySemanticsLabel('$name 쓰다듬기'));
        expect(character.right, lessThan(panel().left), reason: name);
        expect(character.left, greaterThanOrEqualTo(0), reason: name);
      }
      await tester.enterText(
        find.byKey(const ValueKey('house-chat-field')),
        '같이 놀자',
      );
      await tester.pump();
      await tester.tap(find.byTooltip('보내기'));
      await tester.pump(const Duration(milliseconds: 600));
      // 답은 친구의 말풍선으로 나오고, 대화창에도 함께 쌓인다.
      expect(find.byType(SceneSpeech), findsOneWidget);
      expect(
        tester.widget<SceneSpeech>(find.byType(SceneSpeech)).text,
        contains('구름'),
      );
      void bubbleInRoom(double floor) {
        final bubble = tester.getRect(find.byType(SceneSpeech));
        expect(bubble.left, greaterThanOrEqualTo(0));
        expect(bubble.top, greaterThanOrEqualTo(0));
        expect(bubble.right, lessThan(panel().left));
        expect(bubble.bottom, lessThanOrEqualTo(floor));
      }

      bubbleInRoom(size.height);
      expect(
        find.descendant(
          of: find.byType(ChatPanel),
          matching: find.byWidgetPredicate(
            (w) => w is Text && (w.semanticsLabel ?? '').contains('구름'),
          ),
        ),
        findsOneWidget,
      );
      await capture(tester, 'reply-${size.width.toInt()}');
      tester.view.viewInsets = const FakeViewPadding(bottom: 350);
      await tester.pumpAndSettle();
      final dock = panel();
      expect(dock.bottom, lessThanOrEqualTo(size.height - 350));
      expect(dock.top, greaterThanOrEqualTo(0));
      for (final name in ['뭉글이', '뚜치']) {
        final character = tester.getRect(find.bySemanticsLabel('$name 쓰다듬기'));
        expect(character.bottom, lessThan(size.height - 350));
        expect(character.top, greaterThanOrEqualTo(0));
        expect(character.right, lessThan(dock.left));
      }
      bubbleInRoom(size.height - 350);
      final rug = tester.getRect(find.byKey(const ValueKey('house-rug')));
      expect(rug.bottom, lessThanOrEqualTo(size.height - 350));
      await capture(tester, 'keyboard-${size.width.toInt()}');
      expect(tester.takeException(), isNull);
      tester.view.resetViewInsets();
      await tester.pumpWidget(const SizedBox());
    });
  }
}
