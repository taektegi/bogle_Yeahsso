import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/data/local_store.dart';
import 'package:bogle_app/src/data/window_view.dart';
import 'package:bogle_app/src/drawing/studio_draft.dart';
import 'package:bogle_app/src/screens/create_studio_screen.dart';
import 'package:bogle_app/src/screens/friend_screen.dart';
import 'package:bogle_app/src/screens/house/house_widgets.dart';
import 'package:bogle_app/src/theme/bogle_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'order_demo_flow_test.dart' as orders;
import 'house_details_test.dart' as house;

void main() {
  orders.main();
  house.main();
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  Future<void> frames(WidgetTester tester, int ms) async {
    for (var i = 0; i < ms; i += 50) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(tester.takeException(), isNull);
  }

  testWidgets('iPad: 스케치북 이동·고정 도구·초안 복원', (tester) async {
    final store = MemoryStore();
    final draft = StudioDraft(store: store);
    await draft.ready;
    draft.pencilOnly = true;
    final friends = InMemoryCharacterRepository();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildBogleTheme(),
        home: CreateStudioScreen(repository: friends, draft: draft),
      ),
    );
    await frames(tester, 900);
    final canvas = find.byKey(const ValueKey('drawing-canvas'));
    final c = tester.getCenter(canvas);
    final pen = await tester.startGesture(
      c - const Offset(100, 0),
      kind: PointerDeviceKind.stylus,
      pointer: 81,
    );
    for (var i = 1; i <= 15; i++) {
      await pen.moveBy(Offset(10, i.isEven ? 5 : -5));
      await tester.pump();
    }
    await pen.up();
    await frames(tester, 400);
    expect(draft.drawing.strokeCount, 1);
    final a = await tester.startGesture(c - const Offset(40, 0), pointer: 82);
    final b = await tester.startGesture(c + const Offset(40, 0), pointer: 83);
    await a.moveBy(const Offset(-60, 0));
    await b.moveBy(const Offset(60, 0));
    await a.up();
    await b.up();
    await frames(tester, 300);
    expect(find.text('250%'), findsOneWidget);
    final before = draft.pan.dx;
    await tester.dragFrom(c, const Offset(60, 0));
    await frames(tester, 250);
    expect(draft.pan.dx, greaterThan(before));
    expect(draft.drawing.strokeCount, 1);
    expect(tester.getRect(find.byTooltip('펜')).width, greaterThanOrEqualTo(44));
    await tester.tap(find.byTooltip('도구 숨기기'));
    await frames(tester, 300);
    expect(find.byTooltip('되돌리기').hitTestable(), findsOneWidget);
    await binding.takeScreenshot('sketchbook-pan');
    await draft.flush();
    await tester.pumpWidget(const SizedBox());
    draft.dispose();
    final restored = StudioDraft(store: store);
    await restored.ready;
    expect(restored.drawing.strokeCount, 1);
    expect(restored.scale, 2.5);
    expect(restored.pencilOnly, isTrue);
    restored.dispose();
    binding.reportData = {
      ...?binding.reportData,
      'sketchbookPanAndRestore': true,
    };
  });

  testWidgets('iPad: 캐릭터별 배경과 실제 그려진 영역의 크기', (tester) async {
    final repo = InMemoryCharacterRepository();
    final friends = await repo.fetchFriends();
    final sizes = <String, List<double>>{};
    for (final friend in friends) {
      final look = await artLookOf(friend.assetPath);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildBogleTheme(),
          builder: (_, child) => MediaQuery(
            data: MediaQueryData(
              size: tester.view.physicalSize / tester.view.devicePixelRatio,
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: FriendScreen(
            key: ValueKey(friend.id),
            repository: repo,
            friend: friend,
            clock: () => DateTime(2026, 10, 30, 14),
          ),
        ),
      );
      await frames(tester, 900);
      final rect = tester.getRect(find.byType(FriendFigure));
      sizes[friend.id] = [
        rect.width * (look?.drawn.width ?? 1),
        rect.height * (look?.drawn.height ?? 1),
      ];
      expect(sizes[friend.id]!.every((s) => s.isFinite && s > 0), isTrue);
      expect(
        WindowView.forFriend(friend).day,
        contains(friend.id == 'mungle' ? 'aquarium' : friend.id),
      );
      await binding.takeScreenshot('house-${friend.id}');
    }
    final mungle = sizes['mungle']!, ppojik = sizes['ppojik']!;
    final ratio = (ppojik[0] * ppojik[1]) / (mungle[0] * mungle[1]);
    expect(ratio, inInclusiveRange(.65, 1.4));
    binding.reportData = {
      ...?binding.reportData,
      'paintedCharacterSizes': sizes,
      'ppojikToMungleAreaRatio': ratio,
      'distinctStarterViews': true,
    };
    await tester.pumpWidget(const SizedBox());
  });
}
