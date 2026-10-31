import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/data/order_repository.dart';
import 'package:bogle_app/src/screens/order/address_book_screen.dart';
import 'package:bogle_app/src/screens/order/payment_methods_screen.dart';
import 'package:bogle_app/src/screens/order/postcode_search.dart';
import 'package:bogle_app/src/screens/order_screen.dart';
import 'package:bogle_app/src/screens/profile_screen.dart';
import 'package:bogle_app/src/theme/bogle_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  Future<void> frames(WidgetTester tester, int milliseconds) async {
    for (var t = 0; t < milliseconds; t += 50) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(tester.takeException(), isNull);
  }

  testWidgets(
    '실제 iPad WKWebView에서 실주소 검색 결과를 받는다',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildBogleTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          const PostcodeSearchScreen(initialQuery: '세종대로 110'),
                    ),
                  ),
                  child: const Text('실주소 검색 열기'),
                ),
              ),
            ),
          ),
        ),
      );
      await frames(tester, 500);
      await tester.tap(find.text('실주소 검색 열기'));
      await frames(tester, 1000);
      final dynamic state = tester.state(find.byType(PostcodeSearchScreen));
      for (
        var wait = 0;
        wait < 30000 && state.debugResultCount == null;
        wait += 500
      ) {
        await frames(tester, 500);
      }
      expect(
        state.debugResultCount,
        isNotNull,
        reason: 'Official postcode service must return results over HTTPS.',
      );
      expect(state.debugResultCount as int, greaterThan(0));
      await binding.takeScreenshot('live-address-search');
      binding.reportData = {
        ...?binding.reportData,
        'liveAddressSearchResultCount': state.debugResultCount,
      };
      await tester.pageBack();
      await frames(tester, 500);
      await tester.pumpWidget(const SizedBox());
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    '실제 iPad: 마이페이지 관리 → 주문 → 결제 완료 → 주문 내역',
    (tester) async {
      // Device storage is deliberately not attached: all test edits stay in memory.
      tester.testTextInput.register();
      addTearDown(tester.testTextInput.unregister);
      final orders = InMemoryOrderRepository();
      final friends = InMemoryCharacterRepository();
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildBogleTheme(),
          home: ProfileScreen(
            repository: friends,
            orderRepository: orders,
            searchAddress: (_) async =>
                const PostcodeAddress(zip: '04524', street: '서울 중구 세종대로 110'),
          ),
        ),
      );
      await frames(tester, 900);
      await tester.ensureVisible(find.text('배송지 관리'));
      await tester.tap(find.text('배송지 관리'));
      await frames(tester, 600);
      await tester.tap(find.widgetWithText(FilledButton, '새 배송지 추가'));
      await frames(tester, 400);
      await tester.tap(find.byKey(const ValueKey('address-search')));
      await frames(tester, 300);
      await tester.enterText(
        find.byKey(const ValueKey('address-recipient')),
        '김보글',
      );
      await tester.enterText(
        find.byKey(const ValueKey('address-phone')),
        '010-1234-5678',
      );
      await tester.enterText(
        find.byKey(const ValueKey('address-detail')),
        '2층',
      );
      await tester.pump();
      FocusManager.instance.primaryFocus?.unfocus();
      await frames(tester, 500);
      await tester.ensureVisible(find.byKey(const ValueKey('address-save')));
      await binding.takeScreenshot('address-form');
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('address-save')))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byKey(const ValueKey('address-save')));
      await frames(tester, 600);
      expect((await orders.fetchAddresses()).single.isDefault, isTrue);
      await binding.takeScreenshot('address-book');
      await tester.pageBack();
      await frames(tester, 600);
      await tester.ensureVisible(find.text('결제 수단 관리'));
      await tester.tap(find.text('결제 수단 관리'));
      await frames(tester, 500);
      await tester.tap(find.widgetWithText(FilledButton, '결제 수단 추가'));
      await frames(tester, 400);
      await tester.enterText(
        find.byKey(const ValueKey('payment-nickname')),
        '심사 카드',
      );
      await tester.enterText(
        find.byKey(const ValueKey('payment-last4')),
        '1234',
      );
      await tester.pump();
      FocusManager.instance.primaryFocus?.unfocus();
      await frames(tester, 500);
      await tester.ensureVisible(
        find.byKey(const ValueKey('payment-method-save')),
      );
      await tester.tap(find.byKey(const ValueKey('payment-method-save')));
      await frames(tester, 500);
      expect((await orders.fetchPaymentMethods()).single.isDefault, isTrue);
      await binding.takeScreenshot('payment-methods');
      await tester.pageBack();
      await frames(tester, 500);
      await tester.ensureVisible(find.text('인형 만들러 가기'));
      await tester.tap(find.text('인형 만들러 가기'));
      await frames(tester, 900);
      expect(find.byType(OrderScreen), findsOneWidget);
      await tester.tap(find.text('뭉글이 인형 만들기'));
      await frames(tester, 500);
      await tester.tap(find.text('주문하기'));
      await frames(tester, 700);
      expect(find.text('신한카드 · 1234'), findsOneWidget);
      await tester.ensureVisible(find.text('보호자가 주문 내용을 확인했고, 결제에 동의해요'));
      await tester.tap(find.text('보호자가 주문 내용을 확인했고, 결제에 동의해요'));
      await tester.pump();
      final pay = find.widgetWithText(FilledButton, '32,000원 결제하기');
      await tester.ensureVisible(pay);
      await binding.takeScreenshot('checkout');
      await tester.tap(pay);
      await frames(tester, 1800);
      final placed = (await orders.fetchOrders()).single;
      expect(placed.paymentCompleted && placed.simulatedPayment, isTrue);
      expect(placed.paymentMethod, '신한카드 · 1234');
      expect(placed.shipping!.address, contains('세종대로 110 2층'));
      expect(find.text('주문 완료'), findsOneWidget);
      await binding.takeScreenshot('payment-complete');
      Navigator.of(tester.element(find.byType(OrderScreen))).pop();
      await frames(tester, 700);
      await tester.ensureVisible(find.text('주문 내역'));
      expect(find.text('결제 완료'), findsOneWidget);
      await binding.takeScreenshot('profile-order');
      binding.reportData = {
        ...?binding.reportData,
        'simulatedPaymentCompleted':
            placed.paymentCompleted && placed.simulatedPayment,
        'orderCount': (await orders.fetchOrders()).length,
        'addressCount': (await orders.fetchAddresses()).length,
        'paymentMethodCount': (await orders.fetchPaymentMethods()).length,
        'repositories': 'memory only; no charge or user data writes',
      };
      expect(find.byType(AddressBookScreen), findsNothing);
      expect(find.byType(PaymentMethodsScreen), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
