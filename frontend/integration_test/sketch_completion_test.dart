import 'dart:async';

import 'package:bogle_app/src/data/app_services.dart';
import 'package:bogle_app/src/data/character_generation.dart';
import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/data/local_store.dart';
import 'package:bogle_app/src/drawing/studio_draft.dart';
import 'package:bogle_app/src/screens/create_studio_screen.dart';
import 'package:bogle_app/src/screens/loading_screen.dart';
import 'package:bogle_app/src/screens/setup_friend_screen.dart';
import 'package:bogle_app/src/theme/bogle_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

class _Job implements CharacterGenerationJob {
  final done = Completer<GeneratedArt>();
  @override
  Future<GeneratedArt> get result => done.future;
  @override
  void cancel() {}
}

class _Generator implements CharacterGenerator {
  final job = _Job();
  GenerationInput? input;
  @override
  CharacterGenerationJob start(GenerationInput input) {
    this.input = input;
    return job;
  }

  @override
  Future<CharacterGenerationJob?> unfinished() async => null;
  @override
  Future<void> finished(String jobId) async {}
  @override
  Future<void>? faceStillComing(String jobId) => null;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  Future<void> frames(WidgetTester tester, int ms) async {
    for (var i = 0; i < ms; i += 50) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(tester.takeException(), isNull);
  }

  testWidgets('iPad: 그림 생성 성공 후 새 스케치북과 재시작 초안이 비어 있다', (tester) async {
    final store = MemoryStore();
    final draft = StudioDraft(store: store);
    await draft.ready;
    final repo = InMemoryCharacterRepository();
    final generator = _Generator();
    await tester.pumpWidget(
      StudioDraftScope(
        draft: draft,
        child: AppServicesScope(
          services: AppServices.local(characters: repo, generator: generator),
          child: MaterialApp(
            theme: buildBogleTheme(),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => CreateStudioScreen(repository: repo),
                      ),
                    ),
                    child: const Text('스케치북 열기'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('스케치북 열기'));
    await frames(tester, 800);
    final canvas = find.byKey(const ValueKey('drawing-canvas'));
    final center = tester.getCenter(canvas);
    final pen = await tester.startGesture(
      center - const Offset(90, 0),
      kind: PointerDeviceKind.stylus,
      pointer: 51,
    );
    for (var i = 0; i < 15; i++) {
      await pen.moveBy(Offset(10, i.isEven ? 8 : -8));
      await tester.pump();
    }
    await pen.up();
    await frames(tester, 500);
    expect(draft.drawing.hasInk, true);
    await binding.takeScreenshot('before-generation');
    await tester.tap(find.byKey(const ValueKey('studio-create')));
    await frames(tester, 5000);
    expect(find.byType(LoadingScreen), findsOneWidget);
    expect(draft.drawing.hasInk, true);
    expect(generator.input!.image, isNotEmpty);
    generator.job.done.complete(
      const GeneratedArt(assetPath: 'assets/figma/character_friend.svg'),
    );
    await frames(tester, 2000);
    expect(find.byType(SetupFriendScreen), findsOneWidget);
    expect(draft.drawing.isEmpty, true);
    expect(draft.drawing.canUndo, false);
    await tester.tap(find.byKey(const ValueKey('bogle-home-button')).last);
    await frames(tester, 700);
    await tester.tap(find.text('스케치북 열기'));
    await frames(tester, 700);
    expect(draft.drawing.isEmpty, true);
    expect(draft.drawing.canUndo, false);
    expect(draft.scale, 1);
    await binding.takeScreenshot('new-blank-sketchbook');
    await draft.flush();
    await tester.pumpWidget(const SizedBox());
    draft.dispose();
    final restored = StudioDraft(store: store);
    await restored.ready;
    expect(restored.drawing.isEmpty, true);
    expect(restored.drawing.canUndo, false);
    expect(generator.input!.image, isNotEmpty);
    binding.reportData = {
      ...?binding.reportData,
      'pendingKeepsDrawing': true,
      'successClearsDrawing': true,
      'reopenedBlank': true,
      'restoredBlank': true,
      'undoEmpty': true,
      'inputBytesPreserved': generator.input!.image.length,
    };
    restored.dispose();
  });
}
