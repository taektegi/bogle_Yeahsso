import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/data/order_repository.dart';
import 'package:bogle_app/src/screens/order_screen.dart';
import 'package:bogle_app/src/theme/bogle_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// 작은 iPad에서도 옵션·결제 화면이 스크롤 없이 한 화면에 들어오는지 본다.
/// 기기 데이터에 연결하지 않는 세션 전용 저장소를 쓴다.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  Future<void> frames(WidgetTester tester, int milliseconds) async {
    for (var t = 0; t < milliseconds; t += 50) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(tester.takeException(), isNull);
  }

  testWidgets('실제 iPad: 주문 옵션·결제 한 화면', (tester) async {
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
                phone: '010-1234-5678',
                zip: '04524',
                street: '서울특별시 중구 세종대로 110',
                detail: '보글아파트 101동 1203호',
                isDefault: true,
              ),
            ],
          ),
        ),
      ),
    );
    await frames(tester, 1500);
    List<double> scrolling() => [
      for (final state in tester.stateList<ScrollableState>(
        find.byType(Scrollable),
      ))
        if (state.position.maxScrollExtent > .5 &&
            state.axisDirection == AxisDirection.down)
          state.position.maxScrollExtent,
    ];
    await tester.tap(find.text('뭉글이 인형 만들기'));
    await frames(tester, 800);
    expect(scrolling(), isEmpty);
    await binding.takeScreenshot('order-options');
    await tester.tap(find.text('주문하기'));
    await frames(tester, 800);
    expect(scrolling(), isEmpty);
    await binding.takeScreenshot('order-checkout');
    await tester.pumpWidget(const SizedBox());
  });
}
