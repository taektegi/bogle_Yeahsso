import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:bogle_app/src/data/character_generation.dart';
import 'package:bogle_app/src/drawing/studio_draft.dart';
import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/screens/loading_screen.dart';
import 'package:bogle_app/src/screens/setup_friend_screen.dart';
import 'package:bogle_app/src/theme/bogle_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const newArt = GeneratedArt(assetPath: 'assets/figma/character_friend.svg');

class ControlledJob implements CharacterGenerationJob {
  final done = Completer<GeneratedArt>();
  bool cancelled = false;
  @override
  Future<GeneratedArt> get result => done.future;
  @override
  void cancel() {
    cancelled = true;
  }
}

Future<void> openLoading(
  WidgetTester tester,
  CharacterGenerationJob Function()? factory, {
  bool reduced = false,
  GenerationInput? input,
  StudioDraft? draft,
}) async {
  tester.view.physicalSize = const Size(1210, 834);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildBogleTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => LoadingScreen(
                  repository: InMemoryCharacterRepository(),
                  input: input,
                  draft: draft,
                  startGeneration: factory,
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 300)),
  );
  await tester.pump(const Duration(milliseconds: 350));
}

Rect revealed(WidgetTester tester) => tester
    .widget<ClipRect>(find.byKey(const ValueKey('wordmark-reveal')))
    .clipper!
    .getClip(const Size(258, 160));

void main() {
  testWidgets('a drawing becomes the new friend without a character service', (
    tester,
  ) async {
    final drawing = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawCircle(
        const Offset(300, 200),
        60,
        Paint()..color = const Color(0xFF8BA2FF),
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(800, 500);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      return png!.buffer.asUint8List();
    });
    await openLoading(
      tester,
      null,
      reduced: true,
      input: GenerationInput(drawing!, source: GenerationSource.drawing),
    );
    // The local generator saves the drawing for real, off the test clock.
    for (
      var i = 0;
      i < 20 && find.byType(SetupFriendScreen).evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(seconds: 1));
    final setup = tester.widget<SetupFriendScreen>(
      find.byType(SetupFriendScreen),
    );
    expect(setup.art.assetPath, endsWith('.png'));
    expect(File(setup.art.assetPath).existsSync(), isTrue);
  });

  testWidgets('home logo cancels loading and prevents late navigation', (
    tester,
  ) async {
    final job = ControlledJob();
    await openLoading(tester, () => job);
    await tester.pump(const Duration(seconds: 8));
    await tester.tap(find.byKey(const ValueKey('bogle-home-button')));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
    expect(find.byType(LoadingScreen), findsNothing);
    expect(job.cancelled, isTrue);
    job.done.complete(newArt);
    await tester.pump(const Duration(seconds: 5));
    expect(find.byType(SetupFriendScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('loading copy reveals whole letters in order on the logo clock', (
    tester,
  ) async {
    final job = ControlledJob();
    await openLoading(tester, () => job);
    final glyphs = tester.widgetList<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('loading-copy-reveal')),
        matching: find.byType(Text),
      ),
    );
    expect(glyphs.length, 7);
    for (final glyph in glyphs) {
      expect(glyph.style?.fontFamily, 'Yangjin');
    }
    double opacity(int i) => tester
        .widget<FadeTransition>(find.byKey(ValueKey('loading-copy-glyph-$i')))
        .opacity
        .value;
    await tester.pump(const Duration(milliseconds: 650));
    final bounds = tester.getRect(
      find.byKey(const ValueKey('loading-copy-reveal')),
    );
    expect(opacity(0), greaterThan(opacity(1)));
    expect(opacity(3), 0);
    // Control Center pulled over the app: still showing, so it carries on.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    final covered = [for (var i = 0; i < 7; i++) opacity(i)];
    for (var k = 0; k < 4; k++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect([for (var i = 0; i < 7; i++) opacity(i)], isNot(covered));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    final paused = [for (var i = 0; i < 7; i++) opacity(i)];
    await tester.pump(const Duration(seconds: 2));
    expect([for (var i = 0; i < 7; i++) opacity(i)], paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1800));
    for (var i = 0; i < 3; i++) {
      expect(opacity(i), 1);
    }
    expect(opacity(4), greaterThanOrEqualTo(opacity(5)));
    expect(opacity(5), greaterThanOrEqualTo(opacity(6)));
    expect(
      tester.getRect(find.byKey(const ValueKey('loading-copy-reveal'))),
      bounds,
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 650));
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.byKey(const ValueKey('loading-copy-reveal')), findsNothing);
    expect(find.byType(SetupFriendScreen), findsNothing);
    job.done.complete(newArt);
    await tester.pumpAndSettle();
    expect(find.byType(SetupFriendScreen), findsOneWidget);
  });

  testWidgets(
    'loading messages dissolve in place instead of switching abruptly',
    (tester) async {
      final job = ControlledJob();
      await openLoading(tester, () => job);
      await tester.pump(const Duration(seconds: 1));
      final switcher = find.byKey(const ValueKey('loading-copy-switcher'));
      final bounds = tester.getRect(switcher);
      await tester.pump(const Duration(seconds: 3));
      final arriving = find.byKey(const ValueKey('loading-copy-arriving'));
      final copy = tester.widget<Text>(find.text('친구가 찾아오는 중'));
      expect(copy.data, '친구가 찾아오는 중');
      expect(copy.style?.fontFamily, 'Yangjin');
      double incomingOpacity() => tester
          .widget<FadeTransition>(
            find
                .ancestor(of: arriving, matching: find.byType(FadeTransition))
                .first,
          )
          .opacity
          .value;
      expect(incomingOpacity(), 0);
      expect(find.byKey(const ValueKey('loading-copy-reveal')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 325));
      expect(incomingOpacity(), closeTo(.5, .02));
      expect(find.byKey(const ValueKey('loading-copy-reveal')), findsOneWidget);
      expect(tester.getRect(switcher), bounds);
      await tester.pump(const Duration(milliseconds: 325));
      expect(incomingOpacity(), 1);
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byKey(const ValueKey('loading-copy-reveal')), findsNothing);
      expect(tester.getRect(switcher), bounds);
      expect(find.byType(SetupFriendScreen), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'arrival dots repeat without moving the copy and pause in background',
    (tester) async {
      final job = ControlledJob();
      await openLoading(tester, () => job);
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
      final bounds = tester.getRect(find.text('친구가 찾아오는 중'));
      List<double> dots() => [
        for (var i = 0; i < 3; i++)
          tester
              .widget<Opacity>(find.byKey(ValueKey('arriving-dot-$i')))
              .opacity,
      ];
      expect(dots(), [0, 0, 0]);
      await tester.pump(const Duration(milliseconds: 250));
      expect(dots(), [1, 0, 0]);
      await tester.pump(const Duration(milliseconds: 400));
      expect(dots(), [1, 1, 0]);
      await tester.pump(const Duration(milliseconds: 400));
      expect(dots(), [1, 1, 1]);
      await tester.pump(const Duration(milliseconds: 1000));
      expect(dots(), [0, 0, 0]);
      await tester.pump(const Duration(milliseconds: 400));
      expect(dots(), [1, 0, 0]);
      expect(tester.getRect(find.text('친구가 찾아오는 중')), bounds);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      final paused = dots();
      await tester.pump(const Duration(seconds: 3));
      expect(dots(), paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(dots(), [1, 1, 0]);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('arrival dots remain static with reduced motion', (tester) async {
    await openLoading(tester, ControlledJob.new, reduced: true);
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(ValueKey('arriving-dot-$i')),
                matching: find.byType(Text),
              ),
            )
            .data
            ?.trim(),
        '·',
      );
      expect(
        tester.widget<Opacity>(find.byKey(ValueKey('arriving-dot-$i'))).opacity,
        1,
      );
    }
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('return label and control share the wordmark centre on iPads', (
    tester,
  ) async {
    await openLoading(tester, ControlledJob.new, reduced: true);
    await tester.pumpAndSettle();
    for (final size in [const Size(1024, 768), const Size(1366, 1024)]) {
      tester.view.physicalSize = size;
      await tester.pump();
      final logo = tester.getCenter(
        find.byKey(const ValueKey('wordmark-reveal')),
      );
      final label = tester.getCenter(find.text('그림으로 돌아가기'));
      final button = tester.getRect(
        find.byKey(const ValueKey('loading-return-button')),
      );
      expect(label.dx, closeTo(logo.dx, .01));
      expect(button.center.dx, closeTo(logo.dx, .01));
      expect(button.height, greaterThanOrEqualTo(48));
      expect(button.bottom, lessThan(size.height));
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('fast result waits for reveal; background defers navigation', (
    tester,
  ) async {
    final job = ControlledJob();
    await openLoading(tester, () => job);
    job.done.complete(newArt);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(SetupFriendScreen), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    final pausedClip = revealed(tester);
    await tester.pump(const Duration(seconds: 10));
    expect(revealed(tester), pausedClip);
    expect(find.byType(SetupFriendScreen), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.byType(SetupFriendScreen), findsOneWidget);
  });

  testWidgets('early failure leaves a complete static wordmark', (
    tester,
  ) async {
    final job = ControlledJob();
    await openLoading(tester, () => job);
    job.done.completeError(StateError('generation unavailable'));
    await tester.pumpAndSettle();
    expect(revealed(tester).top, 0);
    expect(find.text('다시 시도'), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('logo reveals bottom-up once and waits for actual completion', (
    tester,
  ) async {
    final job = ControlledJob();
    await openLoading(tester, () => job);
    final first = revealed(tester);
    await tester.pump(const Duration(milliseconds: 1600));
    final middle = revealed(tester);
    expect(middle.top, lessThan(first.top));
    expect(middle.bottom, 160);
    expect(middle.width, 258);
    await tester.pump(const Duration(seconds: 3));
    expect(revealed(tester).top, 0);
    await tester.pump(const Duration(seconds: 30));
    expect(find.textContaining('시간이 조금 더'), findsOneWidget);
    expect(find.byType(SetupFriendScreen), findsNothing);
    await tester.pump(const Duration(seconds: 45));
    expect(find.textContaining('아직 친구를'), findsOneWidget);
    expect(revealed(tester).top, 0);
    job.done.complete(newArt);
    await tester.pumpAndSettle();
    expect(find.byType(SetupFriendScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failure retries; reduced motion has no repeating ticker', (
    tester,
  ) async {
    final jobs = [ControlledJob(), ControlledJob()];
    var index = 0;
    await openLoading(tester, () => jobs[index++], reduced: true);
    await tester.pumpAndSettle();
    expect(revealed(tester).top, 0);
    expect(tester.binding.transientCallbackCount, 0);
    jobs.first.done.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.text('다시 시도'), findsOneWidget);
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(index, 2);
    jobs.last.done.complete(newArt);
    await tester.pumpAndSettle();
    expect(find.byType(SetupFriendScreen), findsOneWidget);
  });

  testWidgets(
    'timeout can retry; late result never advances cancelled attempt',
    (tester) async {
      final jobs = [ControlledJob(), ControlledJob()];
      var index = 0;
      await openLoading(tester, () => jobs[index++]);
      await tester.pump(const Duration(minutes: 5));
      await tester.pumpAndSettle();
      expect(jobs.first.cancelled, isTrue);
      expect(find.text('다시 시도'), findsOneWidget);
      await tester.tap(find.text('다시 시도'));
      await tester.pump();
      jobs.first.done.complete(newArt);
      await tester.pump(const Duration(seconds: 4));
      expect(find.byType(SetupFriendScreen), findsNothing);
      await tester.tap(find.text('그림으로 돌아가기'));
      await tester.pumpAndSettle();
      expect(jobs.last.cancelled, isTrue);
      jobs.last.done.complete(newArt);
      await tester.pumpAndSettle();
      expect(find.text('open'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets("the service's reason is shown; a picture it can't use offers "
      'no retry, a passing problem does', (tester) async {
    final jobs = [ControlledJob(), ControlledJob()];
    var index = 0;
    await openLoading(tester, () => jobs[index++]);
    jobs.first.done.completeError(
      const GenerationError(
        'generation_unavailable',
        '잠시 후 다시 시도해 주세요.',
        retryable: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('잠시 후 다시 시도해 주세요.'), findsOneWidget);
    await tester.tap(find.text('다시 시도'));
    // Not pumpAndSettle: its fake minutes would hit the 5-minute limit.
    await tester.pump(const Duration(seconds: 1));
    jobs.last.done.completeError(
      const GenerationError(
        'generation_rejected',
        '이 그림으로는 친구를 만들지 못했어요. 다른 그림으로 해 볼까요?',
        retryable: false,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('다른 그림으로 해 볼까요?'), findsOneWidget);
    expect(find.text('다시 시도'), findsNothing);
    expect(find.text('그림으로 돌아가기'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a bubble splits it in two, then small ones pop', (
    tester,
  ) async {
    final job = ControlledJob();
    await openLoading(tester, () => job);
    Finder images(int asset) => find.byWidgetPredicate(
      (w) =>
          w is Image &&
          w.image is AssetImage &&
          (w.image as AssetImage).assetName ==
              'assets/figma/generation_bubble_$asset.png',
    );
    final cyan = find.byKey(const ValueKey('bubble-4'));
    expect(cyan, findsOneWidget);
    await tester.tap(cyan, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 700));
    expect(cyan, findsNothing);
    expect(images(4), findsNWidgets(2));
    // 179 → 118 → pop: both small child bubbles pop on the next tap.
    for (var round = 0; round < 2; round++) {
      await tester.tap(images(4).first, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 700));
    }
    expect(tester.takeException(), isNull);
    job.done.complete(newArt);
    await tester.pumpAndSettle();
    expect(find.byType(SetupFriendScreen), findsOneWidget);
  });

  testWidgets('reduced motion bubbles split without starting a ticker', (
    tester,
  ) async {
    final job = ControlledJob();
    await openLoading(tester, () => job, reduced: true);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('bubble-3')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('bubble-3')), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox());
  });
}
