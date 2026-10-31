import 'package:bogle_app/src/data/character_generation.dart';
import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/data/friend_creation_messages.dart';
import 'package:bogle_app/src/screens/friend_screen.dart';
import 'package:bogle_app/src/screens/house/house_widgets.dart';
import 'package:bogle_app/src/screens/setup_friend_screen.dart';
import 'package:bogle_app/src/theme/bogle_theme.dart';
import 'package:bogle_app/src/widgets/fireworks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/top_bar_expect.dart';

/// Hears [words] as soon as it starts; [available] false acts like a device
/// without speech recognition.
class FakeVoice implements VoiceInput {
  FakeVoice(this.words, {this.available = true});
  final String words;
  final bool available;
  VoidCallback? _done;

  @override
  Future<bool> start(ValueChanged<String> onWords, VoidCallback onDone) async {
    if (!available) return false;
    _done = onDone;
    onWords(words);
    return true;
  }

  @override
  Future<void> stop() async {
    _done?.call();
    _done = null;
  }
}

Future<InMemoryCharacterRepository> open(
  WidgetTester tester,
  VoiceInput voice, {
  Size size = const Size(1366, 1024),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = InMemoryCharacterRepository();
  await tester.pumpWidget(
    MaterialApp(
      theme: buildBogleTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: SetupFriendScreen(
        art: const GeneratedArt(assetPath: 'assets/figma/character_friend.svg'),
        repository: repo,
        voice: voice,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  testWidgets(
    'name field keeps its input connection when the iPad keyboard resizes the scene',
    (tester) async {
      await open(tester, FakeVoice('보글'), size: const Size(1194, 834));
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pumpAndSettle();
      await tester.tap(find.text('글자로 적기'));
      await tester.pumpAndSettle();
      final input = tester.state<EditableTextState>(find.byType(EditableText));
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('setup-answer')))
            .focusNode!
            .hasFocus,
        isTrue,
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 360);
      await tester.pumpAndSettle();
      expect(
        tester.state<EditableTextState>(find.byType(EditableText)),
        same(input),
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('setup-answer')))
            .focusNode!
            .hasFocus,
        isTrue,
      );
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '보글',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );
      await tester.pump();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('setup-answer')))
            .controller!
            .text,
        '보글',
      );
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(
        tester.state<EditableTextState>(find.byType(EditableText)),
        same(input),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'typing starts at the leading edge without a centered hint caret',
    (tester) async {
      await open(tester, FakeVoice('보글'));
      // The first question follows on its own.
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pumpAndSettle();
      await tester.tap(find.text('글자로 적기'));
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('setup-answer'));
      final next = find.widgetWithText(FilledButton, '다음');

      void expectLeadingCaret() {
        final editable = tester.state<EditableTextState>(
          find.byType(EditableText),
        );
        final render = editable.renderEditable;
        final origin = render.localToGlobal(
          render.getLocalRectForCaret(const TextPosition(offset: 0)).topLeft,
        );
        final bounds = tester.getRect(field);
        expect(origin.dx, inInclusiveRange(bounds.left - 4, bounds.left + 4));
        expect(tester.widget<TextField>(field).textAlign, TextAlign.start);
      }

      expectLeadingCaret();
      expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
      expect(tester.widget<FilledButton>(next).onPressed, isNull);
      expect(
        tester.widget<TextField>(field).decoration!.hintStyle!.fontWeight,
        FontWeight.w400,
      );
      final emptyLeft = tester.getTopLeft(field).dx;
      for (final value in const [
        TextEditingValue(
          text: 'ㅂ',
          selection: TextSelection.collapsed(offset: 1),
          composing: TextRange(start: 0, end: 1),
        ),
        TextEditingValue(
          text: '보',
          selection: TextSelection.collapsed(offset: 1),
          composing: TextRange(start: 0, end: 1),
        ),
        TextEditingValue(
          text: '보글이',
          selection: TextSelection.collapsed(offset: 3),
        ),
      ]) {
        tester.testTextInput.updateEditingValue(value);
        await tester.pump();
        expect(tester.widget<TextField>(field).controller!.value, value);
        expectLeadingCaret();
        expect(tester.getTopLeft(field).dx, emptyLeft);
      }
      expect(tester.widget<FilledButton>(next).onPressed, isNotNull);
      await tester.enterText(field, '');
      await tester.pump();
      expectLeadingCaret();
      expect(tester.widget<FilledButton>(next).onPressed, isNull);
      await tester.enterText(field, '보글이');
      await tester.pump();
      await tester.tap(next);
      await tester.pumpAndSettle();
      // Only the name is typed: personality is chosen from its answers.
      expect(find.text('보글이는 어떤 친구인가요?'), findsOneWidget);
      expect(field, findsNothing);
      expect(find.text('글자로 적기'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in const [
    Size(1024, 768),
    Size(1194, 834),
    Size(1366, 1024),
  ]) {
    testWidgets('setup keeps the shared top bar at $size', (tester) async {
      await open(tester, FakeVoice('보글'), size: size);
      expectTopBar(tester, pill: 'Setting');
      // The first question follows on its own.
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pumpAndSettle();
      expectTopBar(tester, pill: 'Setting');
      await tester.tap(find.text('글자로 적기'));
      await tester.pumpAndSettle();
      expectTopBar(tester, pill: 'Setting');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('after arriving, the first question comes by itself', (
    tester,
  ) async {
    await open(tester, FakeVoice('보글'));
    expect(find.text('친구가 찾아왔어요!'), findsOneWidget);
    expect(find.text('이름 지어 주기'), findsNothing);
    // A moment to take the friend in first.
    await tester.pump(const Duration(milliseconds: 1000));
    expect(find.text('친구가 찾아왔어요!'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('이 친구에 대해 알려주세요! 이 친구의 이름은 뭐예요?'), findsOneWidget);
  });

  testWidgets('a tap anywhere moves on from the arrival at once', (
    tester,
  ) async {
    await open(tester, FakeVoice('보글'));
    expect(find.text('친구가 찾아왔어요!'), findsOneWidget);
    await tester.tapAt(const Offset(200, 600));
    await tester.pumpAndSettle();
    expect(find.text('이 친구에 대해 알려주세요! 이 친구의 이름은 뭐예요?'), findsOneWidget);
    // The pause's own move-on doesn't skip a question afterwards.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('이 친구에 대해 알려주세요! 이 친구의 이름은 뭐예요?'), findsOneWidget);
  });

  testWidgets('answers one question at a time, then the friend greets', (
    tester,
  ) async {
    final repo = await open(tester, FakeVoice('보글보글'));
    expect(find.text('친구가 찾아왔어요!'), findsOneWidget);
    expectTopBar(tester, pill: 'Setting');
    // The first question follows on its own.
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();

    // Name by voice: the words land in the answer pill.
    expect(find.text('이 친구에 대해 알려주세요! 이 친구의 이름은 뭐예요?'), findsOneWidget);
    expectTopBar(tester, pill: 'Setting');
    await tester.tap(find.text('말로 알려주기'));
    await tester.pumpAndSettle();
    expect(find.text('보글보글'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('그만 듣기'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('다음'));
    await tester.pumpAndSettle();

    // Personality: one of four, by name only. Nothing moves on by itself:
    // a wrong tap is tapped again, and 다음 goes on. The old ways of
    // telling (말로, 글자로) are gone from this question.
    expect(find.text('보글보글은 어떤 친구인가요?'), findsOneWidget);
    expectTopBar(tester, pill: 'Setting');
    expect(find.text('말로 알려주기'), findsNothing);
    expect(find.text('글자로 적기'), findsNothing);
    final next = find.byKey(const ValueKey('setup-next'));
    FilledButton nextButton() => tester.widget<FilledButton>(
      find.descendant(of: next, matching: find.byType(FilledButton)),
    );
    expect(nextButton().onPressed, isNull);
    await tester.tap(find.text('다정한 응원가'));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('보글보글은 어떤 친구인가요?'), findsOneWidget);
    await tester.tap(find.text('엉뚱한 상상가'));
    await tester.pump();
    await tester.tap(next);
    await tester.pumpAndSettle();

    // Favourite things: up to two, then 다음.
    expect(find.text('보글보글이 좋아하는 건 무엇인가요?'), findsOneWidget);
    expect(nextButton().onPressed, isNull);
    await tester.tap(find.text('구름 구경하기'));
    await tester.tap(find.text('노래 부르기'));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('보글보글이 좋아하는 건 무엇인가요?'), findsOneWidget);
    // A third waits for one to be let go.
    await tester.tap(find.text('그림 그리기'));
    await tester.pump();
    await tester.tap(find.text('노래 부르기'));
    await tester.pump();
    await tester.tap(find.text('그림 그리기'));
    await tester.pump();
    await tester.tap(next);
    await tester.pumpAndSettle();

    // Back keeps every answer.
    expect(find.text('보글보글은 어떻게 말하나요?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('setup-back-ink')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('setup-back-ink')));
    await tester.pumpAndSettle();
    expect(find.text('보글보글은 어떤 친구인가요?'), findsOneWidget);
    expect(nextButton().onPressed, isNotNull);
    await tester.tap(next);
    await tester.pumpAndSettle();
    await tester.tap(next);
    await tester.pumpAndSettle();

    // 말투: trying one, the friend says the same line that way, over its
    // own head: the tail's point just above the drawing, the balloon on
    // screen.
    expect(find.text('보글보글은 어떻게 말하나요?'), findsOneWidget);
    expect(find.text('말투를 누르면 미리 볼 수 있어요.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('speech-manner-plain')));
    await tester.pumpAndSettle();
    expectTopBar(tester, pill: 'Setting');
    String said() =>
        tester.widget<SpeechBubble>(find.byType(SpeechBubble)).text;
    expect(said(), '숨바꼭질하자. 내가 먼저 숨을게.');
    final art = tester.getRect(find.bySemanticsLabel('새 친구').first);
    final bubble = tester.getRect(find.byType(SpeechBubble));
    final tip = bubble.left + SpeechBubble.defaultTailRoot - .6 * 24;
    expect(tip, inInclusiveRange(art.left, art.right));
    expect(bubble.bottom, inInclusiveRange(art.top - 30, art.top + 10));
    expect(bubble.left, greaterThanOrEqualTo(0));
    expect(bubble.right, lessThanOrEqualTo(1366));
    await tester.pumpAndSettle();
    expect(said(), '숨바꼭질하자. 내가 먼저 숨을게.');
    await tester.tap(find.byKey(const ValueKey('speech-manner-plain')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('이 말투로 정하기'));
    await tester.pumpAndSettle();

    final saved = (await repo.fetchFriends()).firstWhere(
      (f) => f.name == '보글보글',
    );
    expect(saved.personality, '엉뚱한 상상가');
    expect(saved.favoriteThings, ['구름', '그림']);
    expect(saved.speechStyle, 'plain_casual');
    expect(saved.introduction, '구름 구경과 그림 그리기를 좋아하는 엉뚱한 상상가예요.');

    expect(find.text('친구가 되었어요!'), findsOneWidget);
    expectTopBar(tester, pill: 'Hello');
    // Figma 250:2845: "친구가 되었어요!" above the friend, who talks in
    // the box below it.
    Rect rect(Finder f) => tester.getRect(f);
    final friendArt = find.bySemanticsLabel('새 친구').first;
    expect(rect(find.text('친구가 되었어요!')).bottom, lessThan(rect(friendArt).top));
    expect(
      rect(friendArt).bottom,
      lessThan(rect(find.byKey(const ValueKey('greeting-box'))).top),
    );
    expect(
      rect(find.byKey(const ValueKey('greeting-box'))).width,
      closeTo(900 * 1366 / 1194, 1),
    );
    // Whole words to a line: letters held together by word joiners.
    Finder spoken(String line) => find.byWidgetPredicate(
      (w) => w is Text && w.data?.replaceAll('\u2060', '') == line,
    );
    expect(spoken('안녕, 나는 보글보글이야. 만나서 반가워.'), findsOneWidget);
    Fireworks party() => tester.widget<Fireworks>(find.byType(Fireworks));
    // Held back while the friend says hello.
    expect(party().active, isFalse);
    await tester.tap(find.byKey(const ValueKey('greeting-box')));
    await tester.pumpAndSettle();
    final greeting = find.byWidgetPredicate(
      (w) =>
          w is Text &&
          friendCreationMessages.contains(w.data?.replaceAll('\u2060', '')),
    );
    expect(greeting, findsOneWidget);
    final chosen = tester.widget<Text>(greeting).data!.replaceAll('\u2060', '');
    // Rebuild for iPad size changes: the selected line must stay put and wrap.
    for (final size in [const Size(1024, 768), const Size(1366, 1024)]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      expect(spoken(chosen), findsOneWidget);
      final bubble = tester.getRect(find.byKey(const ValueKey('greeting-box')));
      final copy = tester.getRect(spoken(chosen));
      expect(bubble.contains(copy.topLeft), isTrue);
      expect(bubble.contains(copy.bottomRight), isTrue);
      expect(tester.takeException(), isNull);
    }
    await tester.tap(find.byKey(const ValueKey('greeting-box')));
    await tester.pumpAndSettle();

    // "친구가 되었어요!": the order screen's party poppers, crossing behind
    // the friend and fired from beside the two buttons, over the whole
    // screen so the ribbons can fall past its bottom edge.
    // Figma 299:4128: the friend rises, the line settles under it and the
    // two 402-wide buttons take the box's place.
    expect(rect(friendArt).bottom, lessThan(rect(find.text('친구가 되었어요!')).top));
    final home = rect(find.text('보글보글의 집으로 가기'));
    expect(rect(find.text('친구가 되었어요!')).bottom, lessThan(home.top));
    expect(find.byKey(const ValueKey('greeting-box')), findsNothing);
    expect(party().active, isTrue);
    expect(party().style, FireworksStyle.screenFan);
    expect(party().focusTarget, isNotNull);
    expect(party().keepClear, isNotNull);
    expect(
      tester.getRect(find.byType(Fireworks)),
      tester.getRect(find.byType(Scaffold).first),
    );

    await tester.tap(find.text('보글보글의 집으로 가기'));
    await tester.pumpAndSettle();
    expect(find.byType(FriendScreen), findsOneWidget);
    expect(find.text('보글보글'), findsOneWidget);
  });

  testWidgets('without speech recognition it falls back to typing', (
    tester,
  ) async {
    await open(tester, FakeVoice('', available: false));
    // The first question follows on its own.
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('말로 알려주기'));
    await tester.pumpAndSettle();
    expect(find.textContaining('글자로 적어 주세요'), findsOneWidget);
    expect(find.byKey(const ValueKey('setup-answer')), findsOneWidget);

    expect(tester.takeException(), isNull);
  });
}
