import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bogle_app/src/data/character_generation.dart';
import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/data/order_repository.dart';
import 'package:bogle_app/src/data/profile_repository.dart';
import 'package:bogle_app/src/drawing/drawing_controller.dart';
import 'package:bogle_app/src/drawing/studio_draft.dart';
import 'package:bogle_app/src/models/friend_status.dart';
import 'package:bogle_app/src/screens/archive_screen.dart';
import 'package:bogle_app/src/screens/create_studio_screen.dart';
import 'package:bogle_app/src/screens/order_screen.dart';
import 'package:bogle_app/src/screens/profile_screen.dart';
import 'package:bogle_app/src/theme/bogle_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sample_orders.dart';

void tablet(WidgetTester tester) {
  tester.view.physicalSize = const Size(1194, 834);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<GlobalKey<NavigatorState>> openOrder(
  WidgetTester tester,
  InMemoryOrderRepository orders,
  Future<void> Function() payment,
) async {
  tablet(tester);
  final navigator = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigator,
      theme: buildBogleTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: const Scaffold(body: Text('test-home')),
    ),
  );
  unawaited(
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => OrderScreen(
          repository: InMemoryCharacterRepository(),
          orderRepository: orders,
          confirmPayment: payment,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('뭉글이 인형 만들기'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('주문하기'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('보호자가 주문 내용을 확인했고, 결제에 동의해요'));
  await tester.pump();
  await tester.ensureVisible(find.widgetWithText(FilledButton, '32,000원 결제하기'));
  await tester.pumpAndSettle();
  return navigator;
}

class FailingOrders extends InMemoryOrderRepository {
  FailingOrders() : super(addresses: [sampleAddress]);
  bool fail = true;
  @override
  Future<void> placeOrder(ProfileOrder order) async {
    if (fail) throw StateError('preview offline');
    await super.placeOrder(order);
  }
}

void main() {
  test('generation input is an immutable copy, not a discarded reference', () {
    final bytes = Uint8List.fromList([1, 2, 3]);
    final input = GenerationInput(bytes, source: GenerationSource.photo);
    bytes[0] = 9;
    expect(input.image, [1, 2, 3]);
    expect(() => input.image[0] = 5, throwsUnsupportedError);
  });

  test(
    'ink export rejects blank, invisible, clipped and fully erased pages',
    () async {
      final drawing = DrawingController();
      addTearDown(drawing.dispose);
      const size = Size(100, 100);
      expect(await drawing.exportInk(size), isNull);
      expect(await drawing.hasVisibleInk(size), isFalse);
      drawing.begin(
        const Offset(30, 30),
        Colors.transparent,
        8,
        DrawingTool.pen,
      );
      drawing.end();
      expect(drawing.hasInk, isFalse);
      drawing.begin(const Offset(-100, -100), Colors.blue, 8, DrawingTool.pen);
      drawing.end();
      expect(await drawing.exportInk(size), isNull);
      drawing.clear();
      drawing.begin(const Offset(50, 50), Colors.red, 10, DrawingTool.pen);
      drawing.end();
      final png = await drawing.exportInk(size);
      expect(png, isNotNull);
      expect(await drawing.hasVisibleInk(size), isTrue);
      final codec = await ui.instantiateImageCodec(png!);
      final image = (await codec.getNextFrame()).image;
      expect(image.width, 200);
      expect(image.height, 200);
      image.dispose();
      codec.dispose();
      drawing.begin(const Offset(50, 50), Colors.black, 80, DrawingTool.eraser);
      drawing.end();
      expect(await drawing.exportInk(size), isNull);
      expect(await drawing.hasVisibleInk(size), isFalse);
      drawing.undo();
      expect(await drawing.exportInk(size), isNotNull);
    },
  );

  testWidgets('empty sketch cannot start generation', (tester) async {
    tablet(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildBogleTheme(),
        home: CreateStudioScreen(repository: InMemoryCharacterRepository()),
      ),
    );
    await tester.pumpAndSettle();
    final semantics = find
        .descendant(
          of: find.byTooltip('친구로 만들기'),
          matching: find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.label == '친구로 만들기',
          ),
        )
        .first;
    expect(tester.widget<Semantics>(semantics).properties.enabled, isFalse);
    await tester.tap(find.byTooltip('친구로 만들기'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(CreateStudioScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home and reopening preserve ink, undo and tool settings', (
    tester,
  ) async {
    tablet(tester);
    final draft = StudioDraft();
    addTearDown(draft.dispose);
    final friends = InMemoryCharacterRepository();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildBogleTheme(),
        builder: (_, child) => StudioDraftScope(draft: draft, child: child!),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              child: const Text('open-studio'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CreateStudioScreen(repository: friends),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open-studio'));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('drawing-canvas')),
      const Offset(100, 30),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('형광펜'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bogle-home-button')));
    await tester.pumpAndSettle();
    expect(draft.drawing.strokeCount, 1);
    expect(draft.drawing.canUndo, isTrue);
    expect(draft.tool, DrawingTool.marker);
    await tester.tap(find.text('open-studio'));
    await tester.pumpAndSettle();
    expect(draft.drawing.strokeCount, 1);
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (w) => w is IconButton && w.tooltip == '형광펜',
            ),
          )
          .isSelected,
      isTrue,
    );
    await tester.tap(find.byTooltip('되돌리기'));
    await tester.pump();
    expect(draft.drawing.isEmpty, isTrue);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  test('draft owner can close before the page finishes its active stroke', () {
    final draft = StudioDraft()..attach();
    draft.drawing.begin(const Offset(20, 20), Colors.red, 8, DrawingTool.pen);
    draft.dispose();
    draft.drawing.end();
    expect(draft.drawing.strokeCount, 1);
    draft.detach();
  });

  test(
    'delete/undo restores order, status and every memory exactly once',
    () async {
      final friends = InMemoryCharacterRepository();
      final order = (await friends.fetchFriends()).map((f) => f.id).toList();
      final status = FriendStatus(
        mood: 91,
        fullness: 98,
        energy: 55,
        closeness: 87,
        asleep: true,
        updatedAt: DateTime.now(),
      );
      await friends.saveStatus('mungle', status);
      await friends.addMemory('mungle', '오늘 함께 바다를 그렸어');
      final deleted = await friends.deleteFriend('mungle');
      expect(await friends.fetchMemories('mungle'), isEmpty);
      await friends.restoreFriend(deleted!);
      await friends.restoreFriend(deleted);
      expect((await friends.fetchFriends()).map((f) => f.id), order);
      expect(await friends.fetchStatus('mungle'), same(status));
      expect(await friends.fetchMemories('mungle'), ['오늘 함께 바다를 그렸어']);
    },
  );

  testWidgets('archive undo restores care and memories, not just the card', (
    tester,
  ) async {
    tablet(tester);
    final friends = InMemoryCharacterRepository();
    final status = FriendStatus(closeness: 93, updatedAt: DateTime.now());
    await friends.saveStatus('mungle', status);
    await friends.addMemory('mungle', '우리의 첫 그림');
    await tester.pumpWidget(
      MaterialApp(
        theme: buildBogleTheme(),
        home: ArchiveScreen(repository: friends),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('뭉글이 삭제'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '작별하기').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('다시 데려오기'));
    await tester.pumpAndSettle();
    expect(await friends.fetchStatus('mungle'), same(status));
    expect(await friends.fetchMemories('mungle'), ['우리의 첫 그림']);
    expect((await friends.fetchFriends()).first.id, 'mungle');
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile saved toast cannot collide with quick home/re-entry', (
    tester,
  ) async {
    tablet(tester);
    final profile = InMemoryProfileRepository();
    final friends = InMemoryCharacterRepository();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildBogleTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              child: const Text('open-profile'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ProfileScreen(
                    repository: friends,
                    profileRepository: profile,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open-profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('개인 정보 수정'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('profile-nickname')),
      '별빛',
    );
    await tester.tap(find.text('저장'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const ValueKey('top-action-홈')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open-profile'));
    await tester.pumpAndSettle();
    expect(find.text('안녕, 별빛!'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'payment locks navigation and inputs and rejects double invocation',
    (tester) async {
      final orders = InMemoryOrderRepository(addresses: [sampleAddress]);
      final before = (await orders.fetchOrders()).length;
      final payment = Completer<void>();
      var calls = 0;
      final nav = await openOrder(tester, orders, () {
        calls++;
        return payment.future;
      });
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '32,000원 결제하기'),
      );
      button.onPressed!();
      button.onPressed!();
      await tester.pump();
      expect(calls, 1);
      expect(
        await nav.currentState!.maybePop(),
        isTrue,
      ); // handled, but not popped
      await tester.pump();
      expect(find.byType(OrderScreen), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('top-action-홈')),
        warnIfMissed: false,
      );
      await tester.tap(find.byTooltip('뒤로'), warnIfMissed: false);
      await tester.tap(find.text('배송지 변경'), warnIfMissed: false);
      await tester.pump();
      expect(find.text('배송지 선택'), findsNothing);
      expect(find.text('결제하는 중…'), findsOneWidget);
      payment.complete();
      await tester.pumpAndSettle();
      final placed = await orders.fetchOrders();
      expect(placed.length, before + 1);
      expect(placed.first.price, 32000);
      expect(placed.first.shipping!.recipient, '김보글');
      expect(placed.first.paymentMethod, '간편결제');
      expect(placed.first.deliveryNote, isNotEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'disposing preview during payment does not place a phantom order',
    (tester) async {
      final orders = InMemoryOrderRepository(addresses: [sampleAddress]);
      final before = (await orders.fetchOrders()).length;
      final payment = Completer<void>();
      await openOrder(tester, orders, () => payment.future);
      await tester.tap(find.widgetWithText(FilledButton, '32,000원 결제하기'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      payment.complete();
      await tester.pump();
      expect(await orders.fetchOrders(), hasLength(before));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed order persistence unlocks the page and permits retry', (
    tester,
  ) async {
    final orders = FailingOrders();
    final before = (await orders.fetchOrders()).length;
    await openOrder(tester, orders, () async {});
    await tester.tap(find.widgetWithText(FilledButton, '32,000원 결제하기'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('order-payment-error')), findsOneWidget);
    expect(await orders.fetchOrders(), hasLength(before));
    orders.fail = false;
    await tester.tap(find.widgetWithText(FilledButton, '32,000원 결제하기'));
    await tester.pumpAndSettle();
    expect(await orders.fetchOrders(), hasLength(before + 1));
    expect(find.text('뭉글이가 인형이 되어가는 중이에요!'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'payment request failure is recoverable without recording an order',
    (tester) async {
      final orders = InMemoryOrderRepository(addresses: [sampleAddress]);
      final before = (await orders.fetchOrders()).length;
      var failed = true;
      await openOrder(tester, orders, () async {
        if (failed) throw StateError('preview payment failed');
      });
      await tester.tap(find.widgetWithText(FilledButton, '32,000원 결제하기'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('order-payment-error')), findsOneWidget);
      failed = false;
      await tester.tap(find.widgetWithText(FilledButton, '32,000원 결제하기'));
      await tester.pumpAndSettle();
      expect(await orders.fetchOrders(), hasLength(before + 1));
      expect(tester.takeException(), isNull);
    },
  );

  test('recording the same order twice is idempotent', () async {
    final orders = InMemoryOrderRepository(orders: sampleOrders);
    final order = (await orders.fetchOrders()).first;
    final before = (await orders.fetchOrders()).length;
    await orders.placeOrder(order);
    await orders.placeOrder(order);
    expect(await orders.fetchOrders(), hasLength(before));
  });
}
