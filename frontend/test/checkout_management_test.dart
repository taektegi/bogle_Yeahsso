import 'dart:convert';
import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/data/local_store.dart';
import 'package:bogle_app/src/data/order_catalog.dart';
import 'package:bogle_app/src/data/order_repository.dart';
import 'package:bogle_app/src/screens/order/address_book_screen.dart';
import 'package:bogle_app/src/screens/order/delivery_address_form.dart';
import 'package:bogle_app/src/screens/order/payment_methods_screen.dart';
import 'package:bogle_app/src/screens/order/postcode_search.dart';
import 'package:bogle_app/src/screens/order_screen.dart';
import 'package:bogle_app/src/screens/profile_screen.dart';
import 'package:bogle_app/src/theme/bogle_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DeliveryAddress address(String id, {bool primary = false}) => DeliveryAddress(
  id: id,
  label: id == 'home' ? '우리 집' : '회사',
  recipient: '김보글',
  phone: '010-1234-5678',
  zip: '04524',
  street: '서울 중구 세종대로 110',
  detail: id,
  isDefault: primary,
);
SavedPaymentMethod card(String id, {bool primary = false}) =>
    SavedPaymentMethod(
      id: id,
      kind: PaymentMethod.card,
      provider: '현대카드',
      nickname: id,
      last4: '1234',
      isDefault: primary,
    );
ProfileOrder order(String id) => ProfileOrder(
  id: id,
  product: '민들레 인형',
  asset: 'assets/figma/character_friend.svg',
  options: const ['S'],
  date: '2026.10.30',
  price: 32000,
  status: ProfileOrderStatus.preparing,
  paymentCompleted: true,
  simulatedPayment: true,
  paymentMethod: '현대카드 · 1234',
  shipping: const ShippingInfo(
    recipient: '원래 수령인',
    address: '원래 주소',
    courier: '준비 중',
  ),
);

class _FailingStore extends MemoryStore {
  bool fail = false;
  @override
  Future<void> write(String name, Object? json) {
    if (fail) throw StateError('disk unavailable');
    return super.write(name, json);
  }
}

void main() {
  test(
    'legacy addresses migrate, edit by ID, and keep exactly one default',
    () async {
      final store = MemoryStore();
      await store.write('orders', {
        'addresses': [
          {
            'label': '예전 주소',
            'recipient': '김보글',
            'phone': '01012345678',
            'zip': '04524',
            'street': '서울 중구 세종대로 110',
          },
        ],
      });
      final repo = InMemoryOrderRepository(store: store);
      final legacy = (await repo.fetchAddresses()).single;
      expect(legacy.id, isNotEmpty);
      expect(legacy.isDefault, isTrue);
      await repo.saveAddress(address('home', primary: true));
      await repo.saveAddress(address('work'));
      await repo.saveAddress(address('home', primary: true));
      expect(await repo.fetchAddresses(), hasLength(3));
      await repo.setDefaultAddress('work');
      expect(
        (await repo.fetchAddresses()).singleWhere((a) => a.isDefault).id,
        'work',
      );
      await repo.deleteAddress('work');
      final restored = InMemoryOrderRepository(store: store);
      expect(
        (await restored.fetchAddresses()).where((a) => a.isDefault),
        hasLength(1),
      );
      expect((await restored.fetchAddresses()).first.street, legacy.street);
    },
  );

  test(
    'failed writes roll back orders and settings, and retry saves once',
    () async {
      final store = _FailingStore();
      final repo = InMemoryOrderRepository(store: store);
      await repo.saveAddress(address('home'));
      store.fail = true;
      await expectLater(repo.placeOrder(order('BG-1')), throwsStateError);
      await expectLater(
        repo.saveAddress(address('work', primary: true)),
        throwsStateError,
      );
      await expectLater(repo.savePaymentMethod(card('one')), throwsStateError);
      expect(await repo.fetchOrders(), isEmpty);
      expect((await repo.fetchAddresses()).single.id, 'home');
      expect(await repo.fetchPaymentMethods(), isEmpty);
      store.fail = false;
      await Future.wait([
        repo.placeOrder(order('BG-1')),
        repo.placeOrder(order('BG-1')),
      ]);
      expect(
        await InMemoryOrderRepository(store: store).fetchOrders(),
        hasLength(1),
      );
    },
  );

  test(
    'payment defaults and paid status persist; address book edits do not change an order',
    () async {
      final store = MemoryStore();
      final repo = InMemoryOrderRepository(store: store);
      await Future.wait([
        repo.savePaymentMethod(card('one')),
        repo.savePaymentMethod(card('two')),
      ]);
      await repo.setDefaultPaymentMethod('two');
      await repo.placeOrder(order('BG-2'));
      await repo.saveAddress(address('home'));
      var placed = (await repo.fetchOrders()).single;
      expect(placed.shipping!.address, '원래 주소');
      await repo.updateOrderShipping(placed.id, address('home'));
      await repo.deletePaymentMethod('two');
      final later = InMemoryOrderRepository(store: store);
      expect((await later.fetchPaymentMethods()).single.isDefault, isTrue);
      placed = (await later.fetchOrders()).single;
      expect(placed.shipping!.address, contains('세종대로'));
      expect(placed.paymentCompleted && placed.simulatedPayment, isTrue);
      expect(placed.paymentMethod, '현대카드 · 1234');
      final saved = jsonEncode(await store.read('orders'));
      expect(saved, contains('"last4":"1234"'));
      expect(saved, isNot(contains('cardNumber')));
    },
  );

  test('postcode result validation rejects broken bridge messages', () {
    expect(
      PostcodeAddress.fromMessage({
        'type': 'selected',
        'zip': '123',
        'street': '주소',
      }),
      isNull,
    );
    expect(
      PostcodeAddress.fromMessage({
        'type': 'selected',
        'zip': '04524',
        'street': '',
      }),
      isNull,
    );
    expect(PostcodeAddress.fromMessage({'type': 'ready'}), isNull);
    final selected = PostcodeAddress.fromMessage({
      'type': 'selected',
      'zip': '04524',
      'street': ' 서울 중구 세종대로 110 ',
    });
    expect(selected!.street, '서울 중구 세종대로 110');
  });

  Future<void> open(
    WidgetTester tester,
    Widget home, {
    Size size = const Size(1194, 834),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: buildBogleTheme(), home: home));
    await tester.pumpAndSettle();
  }

  for (final size in [const Size(1024, 768), const Size(1366, 1024)]) {
    testWidgets(
      'address search autofills, details save, editing and deletion work $size',
      (tester) async {
        final repo = InMemoryOrderRepository();
        var searches = 0;
        await open(
          tester,
          AddressBookScreen(
            repository: repo,
            search: (_) async {
              searches++;
              return const PostcodeAddress(
                zip: '04524',
                street: '서울 중구 세종대로 110',
              );
            },
          ),
          size: size,
        );
        await tester.tap(find.widgetWithText(FilledButton, '새 배송지 추가'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('address-search')));
        await tester.pumpAndSettle();
        expect(searches, 1);
        expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('address-zip')))
              .controller!
              .text,
          '04524',
        );
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
        await tester.tap(find.byKey(const ValueKey('address-save')));
        await tester.pumpAndSettle();
        final id = (await repo.fetchAddresses()).single.id;
        expect((await repo.fetchAddresses()).single.isDefault, isTrue);
        await tester.tap(find.text('수정'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('address-detail')),
          '3층',
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('address-save')));
        await tester.pumpAndSettle();
        expect((await repo.fetchAddresses()).single.id, id);
        expect((await repo.fetchAddresses()).single.detail, '3층');
        await tester.tap(find.text('삭제'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, '삭제'));
        await tester.pumpAndSettle();
        expect(await repo.fetchAddresses(), isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'payment method register, edit, delete uses masked display information',
    (tester) async {
      final repo = InMemoryOrderRepository();
      await open(tester, PaymentMethodsScreen(repository: repo));
      await tester.tap(find.widgetWithText(FilledButton, '결제 수단 추가'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('payment-nickname')),
        '심사 카드',
      );
      await tester.enterText(
        find.byKey(const ValueKey('payment-last4')),
        '1234',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('payment-method-save')));
      await tester.pumpAndSettle();
      expect((await repo.fetchPaymentMethods()).single.nickname, '심사 카드');
      await tester.tap(find.text('수정'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('payment-nickname')),
        '새 이름',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('payment-method-save')));
      await tester.pumpAndSettle();
      expect((await repo.fetchPaymentMethods()).single.nickname, '새 이름');
      await tester.tap(find.text('삭제'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '삭제'));
      await tester.pumpAndSettle();
      expect(await repo.fetchPaymentMethods(), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'default address and saved card complete a local payment exactly once',
    (tester) async {
      final repo = InMemoryOrderRepository(
        addresses: [address('work'), address('home', primary: true)],
        paymentMethods: [card('심사 카드', primary: true)],
      );
      await open(
        tester,
        OrderScreen(
          repository: InMemoryCharacterRepository(),
          orderRepository: repo,
        ),
      );
      await tester.tap(find.text('뭉글이 인형 만들기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('주문하기'));
      await tester.pumpAndSettle();
      expect(find.text('현대카드 · 1234'), findsOneWidget);
      expect(find.text('미리보기 버전이라 실제로 결제되지는 않아요'), findsNothing);
      await tester.ensureVisible(find.text('보호자가 주문 내용을 확인했고, 결제에 동의해요'));
      await tester.tap(find.text('보호자가 주문 내용을 확인했고, 결제에 동의해요'));
      await tester.pump();
      final pay = find.widgetWithText(FilledButton, '32,000원 결제하기');
      await tester.ensureVisible(pay);
      await tester.tap(pay);
      await tester.pump();
      expect(find.text('결제하는 중…'), findsOneWidget);
      await tester.pumpAndSettle();
      final placed = (await repo.fetchOrders()).single;
      expect(placed.paymentCompleted && placed.simulatedPayment, isTrue);
      expect(placed.paymentMethod, '현대카드 · 1234');
      expect(placed.shipping!.address, endsWith('home'));
      expect(find.text('주문 완료'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('My Page management rows open working screens', (tester) async {
    final orders = InMemoryOrderRepository();
    await open(
      tester,
      ProfileScreen(
        repository: InMemoryCharacterRepository(),
        orderRepository: orders,
      ),
    );
    await tester.ensureVisible(find.text('배송지 관리'));
    await tester.tap(find.text('배송지 관리'));
    await tester.pumpAndSettle();
    expect(find.byType(AddressBookScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('결제 수단 관리'));
    await tester.tap(find.text('결제 수단 관리'));
    await tester.pumpAndSettle();
    expect(find.byType(PaymentMethodsScreen), findsOneWidget);
    expect(find.byType(DeliveryAddressForm), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
