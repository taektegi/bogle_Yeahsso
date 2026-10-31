import 'dart:async';

import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/data/chat_service.dart';
import 'package:bogle_app/src/data/order_repository.dart';
import 'package:bogle_app/src/models/character_friend.dart';
import 'package:bogle_app/src/models/friend_status.dart';
import 'package:bogle_app/src/screens/create_studio_screen.dart';
import 'package:bogle_app/src/screens/friend_screen.dart';
import 'package:bogle_app/src/screens/house/house_widgets.dart';
import 'package:bogle_app/src/screens/order_screen.dart';
import 'package:bogle_app/src/theme/bogle_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sample_orders.dart';

class _Friends extends InMemoryCharacterRepository {
  _Friends({super.friends});
  bool failRead = false;
  bool failCare = false;
  bool failMemory = false;

  @override
  Future<FriendStatus> fetchStatus(String id) async {
    if (failRead) throw StateError('read failed');
    return super.fetchStatus(id);
  }

  @override
  Future<void> saveStatus(String id, FriendStatus status) async {
    if (failCare) throw StateError('save failed');
    return super.saveStatus(id, status);
  }

  @override
  Future<void> addMemory(String id, String memory) async {
    if (failMemory) throw StateError('memory failed');
    return super.addMemory(id, memory);
  }
}

class _Orders extends InMemoryOrderRepository {
  _Orders({super.addresses});
  bool failRead = false;
  bool failAddress = false;

  @override
  Future<List<ProfileOrder>> fetchOrders() async {
    if (failRead) throw StateError('read failed');
    return super.fetchOrders();
  }

  @override
  Future<void> saveAddress(DeliveryAddress address) async {
    if (failAddress) throw StateError('save failed');
    return super.saveAddress(address);
  }
}

class _SlowChat implements ChatService {
  final reply = Completer<String?>();
  @override
  Future<List<ChatLine>> history(CharacterFriend friend) async => [];
  @override
  Future<String?> replyTo(CharacterFriend friend, String text) => reply.future;
}

Future<void> _show(
  WidgetTester tester,
  Widget screen, {
  double scale = 1,
}) async {
  tester.view.physicalSize = const Size(1024, 768);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildBogleTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: true,
          textScaler: TextScaler.linear(scale),
        ),
        child: child!,
      ),
      home: screen,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _house(
  WidgetTester tester,
  _Friends friends, {
  ChatService? chat,
}) async {
  await _show(
    tester,
    FriendScreen(
      repository: friends,
      friend: (await friends.fetchFriends()).first,
      clock: () => DateTime(2026, 10, 11, 14),
      chat: chat,
    ),
  );
}

Future<void> _checkout(
  WidgetTester tester,
  _Orders orders, {
  double scale = 1,
}) async {
  await _show(
    tester,
    OrderScreen(
      repository: InMemoryCharacterRepository(),
      orderRepository: orders,
    ),
    scale: scale,
  );
  await tester.tap(find.text('뭉글이 인형 만들기'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('주문하기'));
  await tester.tap(find.text('주문하기'));
  await tester.pumpAndSettle();
}

Future<void> _pay(WidgetTester tester) async {
  await tester.ensureVisible(find.text('보호자가 주문 내용을 확인했고, 결제에 동의해요'));
  await tester.tap(find.text('보호자가 주문 내용을 확인했고, 결제에 동의해요'));
  await tester.pump();
  final button = find.widgetWithText(FilledButton, '32,000원 결제하기');
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final friend in await InMemoryCharacterRepository().fetchFriends()) {
      await anchorsFor(friend.assetPath);
    }
  });

  testWidgets('house load failure offers retry and restores the actions', (
    tester,
  ) async {
    final friends = _Friends()..failRead = true;
    await _house(tester, friends);
    expect(find.text('친구의 집을 불러오지 못했어요'), findsOneWidget);
    friends.failRead = false;
    await tester.tap(find.text('다시 불러오기'));
    await tester.pumpAndSettle();
    expect(find.text('친구의 집을 불러오지 못했어요'), findsNothing);
    expect(find.bySemanticsLabel('대화하기'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed care save tells the child and leaves the house usable', (
    tester,
  ) async {
    final friends = _Friends();
    await _house(tester, friends);
    friends.failCare = true;
    await tester.tap(find.byKey(const ValueKey('house-figure')));
    await tester.pumpAndSettle();
    expect(find.text('친구의 돌봄 기록을 저장하지 못했어요.'), findsOneWidget);
    expect(find.bySemanticsLabel('대화하기'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed memory save does not swallow the chat reply', (
    tester,
  ) async {
    final friends = _Friends()..failMemory = true;
    final chat = _SlowChat();
    await _house(tester, friends, chat: chat);
    await tester.tap(find.bySemanticsLabel('대화하기'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('house-chat-field')),
      '안녕!',
    );
    await tester.pump();
    await tester.tap(find.byTooltip('보내기'));
    await tester.pumpAndSettle();
    expect(find.text('이야기를 추억으로 저장하지 못했어요.'), findsOneWidget);
    chat.reply.complete('우리 같이 놀자!');
    await tester.pumpAndSettle();
    expect(chatLine('우리 같이 놀자!'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a delayed chat reply preserves care made while waiting', (
    tester,
  ) async {
    final friends = _Friends();
    final chat = _SlowChat();
    await _house(tester, friends, chat: chat);
    await tester.tap(find.bySemanticsLabel('대화하기'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('house-chat-field')),
      '안녕!',
    );
    await tester.pump();
    await tester.tap(find.byTooltip('보내기'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('house-chat-return')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('house-figure')));
    await tester.pumpAndSettle();
    final before = await friends.fetchStatus('mungle');
    chat.reply.complete('안녕, 반가워!');
    await tester.pumpAndSettle();
    final after = await friends.fetchStatus('mungle');
    expect(after.closeness, (before.closeness + 2).clamp(0, 100));
    expect(after.fullness, before.fullness);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'returning from creation reloads an initially empty doll picker',
    (tester) async {
      final friends = _Friends(friends: []);
      await _show(tester, OrderScreen(repository: friends));
      await tester.tap(find.text('친구 만들러 가기'));
      await tester.pumpAndSettle();
      expect(find.byType(CreateStudioScreen), findsOneWidget);
      await friends.createFriend(
        const NewFriend(
          name: '새친구',
          personality: '다정해요',
          favoriteThings: ['구름'],
          speechStyle: '해요체',
          assetPath: 'assets/figma/character_friend.svg',
          accentHex: 0xFF8BA2FF,
        ),
      );
      Navigator.of(tester.element(find.byType(CreateStudioScreen))).pop();
      await tester.pumpAndSettle();
      expect(find.text('새친구 인형 만들기'), findsOneWidget);
      expect(find.text('인형으로 만들 친구가 아직 없어요'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('address write failure preserves the entered form for retry', (
    tester,
  ) async {
    final orders = _Orders()..failAddress = true;
    await _checkout(tester, orders);
    await tester.tap(find.byKey(const ValueKey('order-add-address')));
    await tester.pumpAndSettle();
    for (final (key, value) in [
      ('recipient', '김보글'),
      ('phone', '010-1234-5678'),
      ('zip', '12345'),
      ('street', '서울 보글로 1'),
    ]) {
      await tester.enterText(find.byKey(ValueKey('address-$key')), value);
    }
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('address-save')));
    await tester.pumpAndSettle();
    expect(find.text('배송지 정보를 저장하지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
    expect(await orders.fetchAddresses(), isEmpty);
    orders.failAddress = false;
    // Failed saves keep the editor open, with all fields intact.
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('address-recipient')))
          .controller!
          .text,
      '김보글',
    );
    await tester.tap(find.byKey(const ValueKey('address-save')));
    await tester.pumpAndSettle();
    expect(await orders.fetchAddresses(), hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('order history read failure can be retried after checkout', (
    tester,
  ) async {
    final orders = _Orders(addresses: [sampleAddress]);
    await _checkout(tester, orders);
    await _pay(tester);
    orders.failRead = true;
    await tester.ensureVisible(find.text('주문 현황 보기'));
    await tester.tap(find.text('주문 현황 보기'));
    await tester.pumpAndSettle();
    expect(find.text('주문 내역을 불러오지 못했어요. 다시 눌러 주세요.'), findsOneWidget);
    orders.failRead = false;
    await tester.tap(find.text('주문 현황 보기'));
    await tester.pumpAndSettle();
    expect(find.text('전체 주문 내역'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a long delivery contact wraps on a small iPad', (tester) async {
    final orders = _Orders(
      addresses: [
        const DeliveryAddress(
          label: '할머니 할아버지 댁',
          recipient: '아주아주긴보호자이름',
          phone: '010-1234-5678',
          zip: '12345',
          street: '서울 보글로 1',
        ),
      ],
    );
    await _checkout(tester, orders, scale: 1.3);
    expect(tester.takeException(), isNull);
  });
}

/// A chat balloon's text: they keep words whole with word joiners.
Finder chatLine(String text) => find.byWidgetPredicate(
  (w) => w is Text && w.data?.replaceAll('\u2060', '') == text,
);
