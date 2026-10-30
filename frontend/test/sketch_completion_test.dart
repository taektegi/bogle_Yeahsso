import 'dart:typed_data';

import 'package:bogle_app/src/data/character_generation.dart';
import 'package:bogle_app/src/data/local_store.dart';
import 'package:bogle_app/src/drawing/drawing_controller.dart';
import 'package:bogle_app/src/drawing/studio_draft.dart';
import 'package:bogle_app/src/screens/setup_friend_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'loading_test.dart' as loading;

void ink(StudioDraft draft) {
  draft.drawing.begin(const Offset(20, 20), Colors.red, 6, DrawingTool.pen);
  draft.drawing.extend(const Offset(100, 70));
  draft.drawing.end();
}

void main() {
  test('생성에 사용한 그림과 undo·redo·확대 위치만 초기화하고 설정은 보존한다', () async {
    final store = MemoryStore();
    final draft = StudioDraft(store: store);
    await draft.ready;
    ink(draft);
    draft.scale = 2.5;
    draft.pan = const Offset(-80, -40);
    draft.color = Colors.blue;
    draft.leftHanded = true;
    draft.paper = Paper.grid;
    final revision = draft.revision;
    await draft.consumeGeneratedDrawing(revision);
    expect(draft.drawing.isEmpty, isTrue);
    expect(draft.drawing.canUndo, isFalse);
    expect(draft.drawing.canRedo, isFalse);
    expect(draft.scale, 1);
    expect(draft.pan, Offset.zero);
    expect(draft.color, Colors.blue);
    expect(draft.leftHanded, isTrue);
    expect(draft.paper, Paper.grid);
    draft.dispose();
    final restored = StudioDraft(store: store);
    await restored.ready;
    expect(restored.drawing.isEmpty, isTrue);
    expect(restored.drawing.canUndo, isFalse);
    expect(restored.color.toARGB32(), Colors.blue.toARGB32());
    restored.dispose();
  });

  test('과거 생성 결과가 나중에 그린 새 그림을 지우지 않는다', () async {
    final draft = StudioDraft(store: MemoryStore());
    await draft.ready;
    ink(draft);
    final old = draft.revision;
    ink(draft);
    await draft.consumeGeneratedDrawing(old);
    expect(draft.drawing.strokeCount, 2);
    draft.dispose();
  });

  test('앱을 다시 열어도 제출한 초안 식별자를 유지해 소비할 수 있다', () async {
    final store = MemoryStore();
    final first = StudioDraft(store: store);
    await first.ready;
    ink(first);
    final submitted = first.revision;
    await first.flush();
    first.dispose();
    final restored = StudioDraft(store: store);
    await restored.ready;
    expect(restored.revision, submitted);
    await restored.consumeGeneratedDrawing(submitted);
    expect(restored.drawing.isEmpty, true);
    restored.dispose();
  });

  for (final source in GenerationSource.values) {
    testWidgets('생성 결과를 받으면 그림 초안만 초기화: $source', (tester) async {
      final draft = StudioDraft(store: MemoryStore());
      await draft.ready;
      ink(draft);
      final job = loading.ControlledJob();
      await loading.openLoading(
        tester,
        () => job,
        reduced: true,
        draft: draft,
        input: GenerationInput(
          Uint8List(0),
          source: source,
          sketchRevision: source == GenerationSource.drawing
              ? draft.revision
              : null,
        ),
      );
      expect(draft.drawing.hasInk, true);
      job.done.complete(loading.newArt);
      await tester.pumpAndSettle();
      expect(find.byType(SetupFriendScreen), findsOneWidget);
      expect(draft.drawing.isEmpty, source == GenerationSource.drawing);
      await tester.pumpWidget(const SizedBox());
      draft.dispose();
    });
  }

  testWidgets('생성 실패·취소와 취소 뒤 늦게 온 성공은 초안을 유지한다', (tester) async {
    final draft = StudioDraft(store: MemoryStore());
    await draft.ready;
    ink(draft);
    final input = GenerationInput(
      Uint8List(0),
      source: GenerationSource.drawing,
      sketchRevision: draft.revision,
    );
    var job = loading.ControlledJob();
    await loading.openLoading(
      tester,
      () => job,
      reduced: true,
      draft: draft,
      input: input,
    );
    job.done.completeError(
      const GenerationError('failed', '다시 시도해 주세요.', retryable: true),
    );
    await tester.pumpAndSettle();
    expect(draft.drawing.hasInk, true);
    await tester.pumpWidget(const SizedBox());
    job = loading.ControlledJob();
    await loading.openLoading(
      tester,
      () => job,
      reduced: true,
      draft: draft,
      input: input,
    );
    await tester.tap(find.byKey(const ValueKey('bogle-home-button')));
    await tester.pumpAndSettle();
    job.done.complete(loading.newArt);
    await tester.pumpAndSettle();
    expect(draft.drawing.hasInk, true);
    expect(find.byType(SetupFriendScreen), findsNothing);
    await tester.pumpWidget(const SizedBox());
    draft.dispose();
  });
}
