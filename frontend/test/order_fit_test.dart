import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/data/order_repository.dart';
import 'package:bogle_app/src/screens/order_screen.dart';
import 'package:bogle_app/src/theme/bogle_theme.dart';
import 'package:bogle_app/src/widgets/fit_to_height.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// iPad models on their side: logical size, status bar, home indicator.
const ipads = [
  ('iPad mini 5', Size(1024, 768), 20.0, 0.0),
  ('iPad 10.2', Size(1080, 810), 20.0, 0.0),
  ('iPad Air 10.5', Size(1112, 834), 20.0, 0.0),
  ('iPad mini 6', Size(1133, 744), 24.0, 20.0),
  ('iPad Air 10.9', Size(1180, 820), 24.0, 20.0),
  ('iPad Pro 11', Size(1194, 834), 24.0, 20.0),
  ('iPad Pro 11 M4', Size(1210, 834), 24.0, 20.0),
  ('iPad Pro 12.9', Size(1366, 1024), 24.0, 20.0),
  ('iPad Pro 13 M4', Size(1376, 1032), 24.0, 20.0),
];

void main() {
  for (final (name, size, top, bottom) in ipads) {
    testWidgets('주문 옵션·결제 화면은 스크롤 없이 한 화면에 들어간다: $name', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.view.padding = FakeViewPadding(top: top, bottom: bottom);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildBogleTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
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
            now: () => DateTime(2026, 9, 27, 10, 30),
          ),
        ),
      );
      await tester.pumpAndSettle();

      /// Scroll views on the page that actually have something to scroll.
      List<String> scrolling() => [
        for (final state in tester.stateList<ScrollableState>(
          find.byType(Scrollable),
        ))
          if (state.position.maxScrollExtent > .5 &&
              state.axisDirection == AxisDirection.down)
            '${state.widget.key ?? state.context.widget.runtimeType}'
                ' ${state.position.maxScrollExtent.toStringAsFixed(1)}',
      ];

      await tester.tap(find.text('뭉글이 인형 만들기'));
      await tester.pumpAndSettle();
      expect(scrolling(), isEmpty, reason: '$name 옵션');
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('주문하기'));
      await tester.pumpAndSettle();
      expect(find.textContaining('결제하기'), findsOneWidget);
      expect(scrolling(), isEmpty, reason: '$name 결제');
      // 줄이더라도 읽기 어려울 만큼 작아지지 않는다.
      final fit = tester.renderObject<RenderFitToHeight>(
        find.byKey(const ValueKey('order-checkout-fit')),
      );
      expect(fit.scale, greaterThanOrEqualTo(.78), reason: name);
      if (size.height >= 1024) expect(fit.scale, 1, reason: name);
      debugPrint('FIT $name ${fit.scale.toStringAsFixed(3)}');
      final pay = tester.getRect(find.textContaining('결제하기'));
      expect(pay.bottom, lessThanOrEqualTo(size.height - bottom));
      expect(tester.takeException(), isNull);
    });
  }
}
