import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/data/order_repository.dart';
import 'package:bogle_app/src/screens/order_screen.dart';
import 'package:bogle_app/src/theme/bogle_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  Future<void> capture(WidgetTester tester, String name, {int ms = 700}) async {
    // Advance multiple frames: one long pump can capture the first frame
    // of a newly-created transition, with the outgoing page still visible.
    for (var elapsed = 0; elapsed < ms; elapsed += 16) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await binding.takeScreenshot(name);
  }

  testWidgets('order: pick, options, checkout, celebration', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildBogleTheme(),
        home: OrderScreen(
          repository: InMemoryCharacterRepository(),
          orderRepository: InMemoryOrderRepository(
            addresses: const [
              DeliveryAddress(
                label: '우리 집',
                recipient: '김보글',
                phone: '010-0000-0000',
                zip: '00000',
                street: '서울특별시 보글구 몽글로 1',
                detail: '보글아파트 101동 1203호',
              ),
            ],
          ),
        ),
      ),
    );
    await capture(tester, 'ipad-order-pick', ms: 1200);
    await tester.tap(find.text('뭉글이 인형 만들기'));
    await capture(tester, 'ipad-order-options');
    await tester.tap(find.byKey(const ValueKey('doll-size-large')));
    await tester.pump(const Duration(milliseconds: 220));
    await tester.tap(find.byKey(const ValueKey('doll-wrap-gift')));
    await capture(tester, 'ipad-order-options-chosen');
    await tester.tap(find.text('주문하기'));
    await capture(tester, 'ipad-order-checkout');
    await tester.tap(find.text('보호자가 주문 내용을 확인했고, 결제에 동의해요'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.textContaining('결제하기'));
    // Catch the one opening pop rather than skipping past it with a long pump.
    for (var i = 0; i < 150; i++) {
      if (find
          .byKey(const ValueKey('fireworks-canvas'))
          .evaluate()
          .isNotEmpty) {
        break;
      }
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.byKey(const ValueKey('fireworks-canvas')), findsOneWidget);
    await capture(tester, 'ipad-order-side-cones', ms: 260);
    await capture(tester, 'ipad-order-side-launch', ms: 180);
    await capture(tester, 'ipad-order-side-arcs', ms: 500);
    await capture(tester, 'ipad-order-side-ribbons');
    await capture(tester, 'ipad-order-side-fall', ms: 1400);
    await capture(tester, 'ipad-order-done', ms: 4000);
    await tester.tap(find.text('주문 현황 보기'));
    await capture(tester, 'ipad-order-status');
    expect(tester.takeException(), isNull);
  });
}
