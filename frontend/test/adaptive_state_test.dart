import 'dart:convert';

import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/data/local_store.dart';
import 'package:bogle_app/src/drawing/drawing_controller.dart';
import 'package:bogle_app/src/drawing/paper_viewport.dart';
import 'package:bogle_app/src/drawing/studio_draft.dart';
import 'package:bogle_app/src/screens/create_studio_screen.dart';
import 'package:bogle_app/src/screens/order_screen.dart';
import 'package:bogle_app/src/theme/bogle_theme.dart';
import 'package:bogle_app/src/widgets/adaptive_panels.dart';
import 'photo_capture_test.dart' show FakeCamera;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final (family, path) in [
      ('Yangjin', 'assets/fonts/Yangjin.ttf'),
      ('Pretendard', 'assets/fonts/Pretendard-Regular.otf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
    ]) {
      await (FontLoader(family)..addFont(rootBundle.load(path))).load();
    }
  });
  test('종이를 균일 배율로 맞추고 확대·이동 좌표를 정확히 역변환한다', () {
    for (final size in [
      const Size(744, 420),
      const Size(1133, 630),
      const Size(1600, 1000),
    ]) {
      final fit = PaperViewport(paper: const Size(1300, 900), viewport: size);
      final rect = MatrixUtils.transformRect(
        fit.transform(),
        Offset.zero & fit.paper,
      );
      expect(rect.left, greaterThanOrEqualTo(-.001));
      expect(rect.top, greaterThanOrEqualTo(-.001));
      expect(rect.right, lessThanOrEqualTo(size.width + .001));
      expect(rect.bottom, lessThanOrEqualTo(size.height + .001));
      expect(rect.width / rect.height, closeTo(1300 / 900, .0001));
      const point = Offset(1100, 750), pan = Offset(-200, -150);
      final displayed = MatrixUtils.transformPoint(
        fit.transform(zoom: 2.2, pan: pan),
        point,
      );
      expect(
        (fit.toPaper(displayed, zoom: 2.2, pan: pan) - point).distance,
        lessThan(.0001),
      );
    }
  });

  test('종이 크기를 저장·복원하며 성공한 생성 뒤 새 종이로 시작한다', () async {
    final store = MemoryStore();
    final draft = StudioDraft(store: store);
    await draft.ready;
    draft.pageSize = const Size(1310, 900);
    draft.drawing.begin(
      const Offset(1200, 800),
      Colors.red,
      6,
      DrawingTool.pen,
    );
    draft.drawing.end();
    await draft.flush();
    draft.dispose();
    final restored = StudioDraft(store: store);
    await restored.ready;
    expect(restored.pageSize, draft.pageSize);
    expect(restored.revision, draft.revision);
    await restored.consumeGeneratedDrawing(restored.revision);
    expect(restored.pageSize, Size.zero);
    restored.dispose();
  });

  test('크기 없는 이전 초안도 되돌릴 수 있는 화면 밖 그림까지 보존한다', () {
    final drawing = DrawingController();
    drawing.begin(const Offset(1200, 800), Colors.red, 10, DrawingTool.pen);
    drawing.end();
    drawing.undo();
    expect(drawing.paperExtent(const Size(700, 400)), const Size(1205, 805));
    drawing.dispose();
  });

  testWidgets('실시간 크기 변경 후 그림·생성 식별자·undo·PNG를 보존하고 입력도 정확하다', (tester) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final draft = StudioDraft(store: MemoryStore());
    await draft.ready;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildBogleTheme(),
        home: CreateStudioScreen(
          repository: InMemoryCharacterRepository(),
          draft: draft,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final canvas = find.byKey(const ValueKey('drawing-canvas'));
    final large = tester.getRect(canvas);
    await tester.dragFrom(
      large.topLeft + const Offset(1000, 600),
      const Offset(50, 20),
    );
    await tester.pumpAndSettle();
    final history = jsonEncode(draft.drawing.snapshot());
    final revision = draft.revision, paper = draft.pageSize;
    final png = await tester.runAsync(() => draft.drawing.exportInk(paper));
    expect(png, isNotNull);
    for (final size in [
      const Size(744, 600),
      const Size(1600, 1200),
      const Size(1024, 768),
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      expect(draft.pageSize, paper);
      expect(draft.revision, revision);
      expect(jsonEncode(draft.drawing.snapshot()), history);
      expect(
        await tester.runAsync(() => draft.drawing.exportInk(draft.pageSize)),
        png,
      );
      expect(tester.takeException(), isNull);
    }
    final small = tester.getRect(canvas);
    final fit = PaperViewport(paper: paper, viewport: small.size);
    const logical = Offset(500, 300);
    final point =
        MatrixUtils.transformPoint(fit.transform(), logical) + small.topLeft;
    await tester.tapAt(point);
    await tester.pumpAndSettle();
    final strokes = draft.drawing.snapshot()['strokes'] as List;
    final points = (strokes.last as Map)['points'] as List;
    final actual = points.first as List;
    expect(actual[0], closeTo(logical.dx, .01));
    expect(actual[1], closeTo(logical.dy, .01));
    await tester.tap(find.byTooltip('되돌리기'));
    await tester.pumpAndSettle();
    expect(draft.drawing.strokeCount, 1);
    await tester.tap(find.byTooltip('다시 실행'));
    await tester.pumpAndSettle();
    expect(draft.drawing.strokeCount, 2);
    await tester.pumpWidget(const SizedBox());
    draft.dispose();
  });

  testWidgets('두 패널을 재배치해도 입력값·포커스 상태를 버리지 않는다', (tester) async {
    tester.view.physicalSize = const Size(1194, 834);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: BoglePanelFlow(
            leading: TextField(key: ValueKey('input')),
            trailing: Text('두 번째 패널'),
          ),
        ),
      ),
    );
    final field = find.byKey(const ValueKey('input'));
    await tester.enterText(field, '민들레의 선물');
    final before = tester.state(find.byType(EditableText));
    tester.view.physicalSize = const Size(744, 600);
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(EditableText)), same(before));
    expect(find.text('민들레의 선물'), findsOneWidget);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      true,
    );
    tester.view.physicalSize = const Size(1194, 834);
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(EditableText)), same(before));
    expect(tester.takeException(), isNull);
  });

  for (final (size, font) in [
    (const Size(744, 600), 1.0),
    (const Size(1024, 600), 2.0),
  ]) {
    testWidgets('좁은 주문 전체 흐름 $size 글자 $font', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildBogleTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: true,
              textScaler: TextScaler.linear(font),
            ),
            child: child!,
          ),
          home: OrderScreen(repository: InMemoryCharacterRepository()),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> tap(Finder target) async {
        await tester.ensureVisible(target);
        await tester.tap(target);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      await tap(find.text('뭉글이 인형 만들기'));
      await tap(find.byKey(const ValueKey('doll-size-large')));
      await tap(find.byKey(const ValueKey('doll-wrap-gift')));
      expect(find.text('51,000원'), findsOneWidget);
      tester.view.physicalSize = const Size(1366, 1024);
      await tester.pumpAndSettle();
      expect(find.text('51,000원'), findsOneWidget);
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      await tap(find.text('주문하기'));
      expect(find.text('총 결제 금액'), findsOneWidget);
      await tap(find.byTooltip('뒤로'));
      expect(find.text('51,000원'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }
  for (final (size, font) in [
    (const Size(1133, 744), 1.0),
    (const Size(744, 600), 2.0),
  ]) {
    testWidgets('사진 촬영·검토·재촬영 자동 적응 $size 글자 $font', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildBogleTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: true,
              textScaler: TextScaler.linear(font),
            ),
            child: child!,
          ),
          home: CreateStudioScreen(
            repository: InMemoryCharacterRepository(),
            camera: FakeCamera.new,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('studio-mode-photo')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final live = tester.getRect(find.byKey(const ValueKey('photo-live')));
      expect(live.width / live.height, closeTo(4 / 3, .01));
      await tester.tap(find.bySemanticsLabel('사진 찍기'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('다시 촬영할래요.'));
      await tester.tap(find.text('다시 촬영할래요.'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('photo-live')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
