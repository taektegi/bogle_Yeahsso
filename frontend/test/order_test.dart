import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bogle_app/src/data/art_source.dart';
import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/models/character_friend.dart';
import 'package:bogle_app/src/data/order_catalog.dart';
import 'package:bogle_app/src/data/order_repository.dart';
import 'package:bogle_app/src/screens/order_screen.dart';
import 'package:bogle_app/src/theme/bogle_theme.dart';
import 'package:bogle_app/src/widgets/bogle_widgets.dart';
import 'package:bogle_app/src/widgets/fireworks.dart';
import 'package:bogle_app/src/widgets/top_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final size in const [Size(1024, 768), Size(1194, 834)]) {
    testWidgets('friend scrolling stays below the heading at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final seed = (await InMemoryCharacterRepository().fetchFriends()).first;
      final friends = [
        for (var i = 0; i < 24; i++)
          CharacterFriend(
            id: 'scroll-friend-$i',
            name: '친구 $i',
            personality: seed.personality,
            favoriteThings: seed.favoriteThings,
            speechStyle: seed.speechStyle,
            assetPath: seed.assetPath,
            accentHex: seed.accentHex,
          ),
      ];
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: MaterialApp(
            theme: buildBogleTheme(),
            home: OrderScreen(
              repository: InMemoryCharacterRepository(friends: friends),
              orderRepository: InMemoryOrderRepository(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final grid = find.byKey(const ValueKey('order-friend-grid'));
      final gridRect = tester.getRect(grid);
      final heading = tester.getRect(find.text('친구 선택'));
      final summary = tester.getRect(
        find.byKey(const ValueKey('order-picked-name')),
      );
      final button = tester.getRect(find.text('친구 0 인형 만들기'));
      final headingBand = Rect.fromLTRB(
        gridRect.left,
        heading.top.floorToDouble(),
        gridRect.right,
        gridRect.top.floorToDouble() - 1,
      );
      Future<Uint8List> pixels(Rect area) async {
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final data = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final bytes = data.buffer.asUint8List();
        final cropped = BytesBuilder();
        for (var y = area.top.toInt(); y < area.bottom; y++) {
          final start = (y * image.width + area.left.toInt()) * 4;
          final end = (y * image.width + area.right.toInt()) * 4;
          cropped.add(bytes.sublist(start, end));
        }
        image.dispose();
        return cropped.takeBytes();
      }

      final lowerBand = Rect.fromLTRB(
        gridRect.left,
        gridRect.bottom.ceilToDouble() + 1,
        gridRect.right,
        button.bottom.ceilToDouble(),
      );
      final before = (await tester.runAsync(() => pixels(headingBand)))!;
      final lowerBefore = (await tester.runAsync(() => pixels(lowerBand)))!;
      await tester.drag(grid, const Offset(0, -110));
      await tester.pumpAndSettle();
      final after = (await tester.runAsync(() => pixels(headingBand)))!;
      expect(
        listEquals(before, after),
        isTrue,
        reason: 'Scrolling cards must not paint over the fixed heading.',
      );
      expect(
        listEquals(
          lowerBefore,
          (await tester.runAsync(() => pixels(lowerBand)))!,
        ),
        isTrue,
        reason: 'Cards must not paint over the summary or action button.',
      );
      // Sample a uniform area of the card artwork as it passes the top edge.
      // Its colour must fade into the panel, rather than stop at a hard cut.
      final scrollable = find.descendant(
        of: grid,
        matching: find.byType(Scrollable),
      );
      final position = tester.state<ScrollableState>(scrollable).position;
      final scale =
          tester.getSize(find.byKey(const ValueKey('order-pick-panel'))).width /
          1108;
      position.jumpTo(40 * scale);
      await tester.pumpAndSettle();
      final x = (gridRect.left + 24 * scale).floorToDouble();
      Future<List<int>> colour(double y) async => (await pixels(
        Rect.fromLTWH(x, y.floorToDouble(), 1, 1),
      )).take(3).toList();
      final background = (await tester.runAsync(
        () => colour(gridRect.top - 2),
      ))!;
      final edge = (await tester.runAsync(() => colour(gridRect.top + 1)))!;
      final middle = (await tester.runAsync(
        () => colour(gridRect.top + 12 * scale),
      ))!;
      final interior = (await tester.runAsync(
        () => colour(gridRect.top + 28 * scale),
      ))!;
      int contrast(List<int> sample) => List.generate(
        3,
        (i) => (sample[i] - background[i]).abs(),
      ).reduce((a, b) => a + b);
      expect(contrast(edge), lessThan(contrast(middle)));
      expect(contrast(middle), lessThan(contrast(interior)));
      expect(tester.getRect(find.text('친구 선택')), heading);
      expect(
        tester.getRect(find.byKey(const ValueKey('order-picked-name'))),
        summary,
      );
      expect(tester.getRect(find.text('친구 0 인형 만들기')), button);
      final offset = position.pixels;
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      final pull = await tester.startGesture(tester.getCenter(grid));
      await pull.moveBy(const Offset(0, -140));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        position.pixels - position.maxScrollExtent,
        lessThan(position.viewportDimension * .15),
        reason: 'The first pull at the end must already meet edge resistance.',
      );
      expect(
        listEquals(
          lowerBefore,
          (await tester.runAsync(() => pixels(lowerBand)))!,
        ),
        isTrue,
      );
      await pull.up();
      await tester.pumpAndSettle();
      expect(position.pixels, closeTo(position.maxScrollExtent, 1));
      position.jumpTo(offset);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('order-friend-scroll-friend-4')),
      );
      await tester.pumpAndSettle();
      expect(position.pixels, closeTo(offset, .01));
      expect(find.text('친구 4 인형 만들기'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final size in const [
    Size(1024, 768),
    Size(1194, 834),
    Size(1366, 1024),
  ]) {
    testWidgets('Figma order panel fits and shares the app top bar at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildBogleTheme(),
          home: OrderScreen(repository: InMemoryCharacterRepository()),
        ),
      );
      await tester.pumpAndSettle();
      final logo = find.byKey(const ValueKey('top-bar-logo'));
      final title = find.text('Order');
      final icons = find.byKey(const ValueKey('top-bar-icons'));
      for (final item in [title, icons]) {
        expect(
          tester.getCenter(item).dy,
          closeTo(tester.getCenter(logo).dy, .01),
        );
      }
      expect(tester.getCenter(title).dx, closeTo(size.width / 2, .01));
      expect(find.byType(AppTopBar), findsOneWidget);
      expect(find.byTooltip('뒤로'), findsOneWidget);
      expect(
        tester.getCenter(find.byKey(const ValueKey('order-pick-question'))).dx,
        tester.getCenter(find.byKey(const ValueKey('order-friend-preview'))).dx,
      );
      await tester.tap(find.text('뭉글이 인형 만들기'));
      await tester.pumpAndSettle();
      final panel = tester.getRect(
        find.byKey(const ValueKey('order-options-panel')),
      );
      final preview = tester.getRect(
        find.byKey(const ValueKey('order-doll-preview')),
      );
      final orderButton = tester.getRect(
        find.widgetWithText(FilledButton, '주문하기'),
      );
      expect(panel.contains(preview.topLeft), isTrue);
      expect(panel.contains(orderButton.bottomRight), isTrue);
      expect(preview.right, lessThan(orderButton.left));
      expect(find.text('사이즈 선택'), findsOneWidget);
      expect(find.text('포장 선택'), findsOneWidget);
      expect(find.text('날 직접 만나 봐 !'), findsOneWidget);
      expect(find.text('총 상품 금액'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('doll-size-large')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('doll-wrap-gift')));
      await tester.pumpAndSettle();
      expect(find.text('51,000원'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('doll-wrap-basic')));
      await tester.pumpAndSettle();
      expect(find.text('48,000원'), findsOneWidget);
      await tester.tap(find.text('주문하기'));
      await tester.pumpAndSettle();
      expect(find.text('총 결제 금액'), findsOneWidget);
      expect(find.text('배송비'), findsOneWidget);
      await tester.tap(find.byTooltip('뒤로'));
      await tester.pumpAndSettle();
      expect(find.text('48,000원'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  test('prices add up and shipping is free from 50,000원', () {
    const basic = DollOrder(size: DollSize.small);
    expect(basic.unitPrice, 29000);
    expect(basic.shipping, 3000);
    expect(basic.total, 32000);

    const big = DollOrder(
      size: DollSize.large,
      material: DollMaterial.fur,
      extras: {DollExtra.giftWrap, DollExtra.nameStitch},
      quantity: 2,
    );
    expect(big.unitPrice, 29000 + 19000 + 4000 + 3000 + 5000);
    expect(big.shipping, 0);
    expect(big.total, 120000);
    expect(big.labels, ['L 사이즈 (45cm)', '몽글 퍼', '선물 포장', '이름 자수']);
  });

  test('order numbers and arrival dates read naturally', () {
    final at = DateTime(2026, 9, 27, 10, 30);
    expect(orderNumber(at), startsWith('BG260927-'));
    expect(koreanDate(estimatedArrival(at)), '10월 9일 (금)');
  });

  testWidgets('pick, options, checkout and a placed order', (tester) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final orders = InMemoryOrderRepository();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildBogleTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: OrderScreen(
          repository: InMemoryCharacterRepository(),
          orderRepository: orders,
          now: () => DateTime(2026, 9, 27, 10, 30),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // ① Pick 뚜치 from the side list.
    expect(find.text('어떤 친구를 인형으로 만들까요?'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('뚜치'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('뚜치 인형 만들기'));
    await tester.pumpAndSettle();

    // ② Options change the total.
    String total() =>
        tester.widget<Text>(find.byKey(const ValueKey('order-total'))).data!;
    expect(total(), '29,000원'); // S, product total excludes checkout shipping.
    await tester.tap(find.byKey(const ValueKey('doll-size-large')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('doll-wrap-gift')));
    await tester.pumpAndSettle();
    expect(total(), '51,000원'); // (29+19+3)k, free shipping
    await tester.tap(find.text('주문하기'));
    await tester.pumpAndSettle();

    // ③ Checkout: paying needs the guardian's consent and somewhere to
    // send the doll; there is no address yet, so one is added.
    expect(find.text('10월 9일 (금)'), findsOneWidget);
    final pay = find.widgetWithText(FilledButton, '51,000원 결제하기');
    await tester.tap(find.text('보호자가 주문 내용을 확인했고, 결제에 동의해요'));
    await tester.pump();
    expect(tester.widget<FilledButton>(pay).onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('order-add-address')));
    await tester.pumpAndSettle();
    final save = find.byKey(const ValueKey('address-save'));
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    for (final (key, text) in const [
      ('label', '할머니 댁'),
      ('recipient', '김순자'),
      ('phone', '010-9876-5432'),
      ('zip', '48058'),
      ('street', '부산광역시 해운대구 해운대해변로 264'),
    ]) {
      await tester.enterText(find.byKey(ValueKey('address-$key')), text);
    }
    await tester.pump();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('김순자'), findsOneWidget);
    expect(await orders.fetchAddresses(), hasLength(1));
    await tester.tap(pay);
    await tester.pumpAndSettle();

    // ④ Done: the order is on My Page too.
    expect(
      tester.widget<Fireworks>(find.byType(Fireworks)).style,
      FireworksStyle.screenFan,
    );
    expect(tester.widget<Fireworks>(find.byType(Fireworks)).handTarget, isNull);
    // Celebration is outside SafeArea/padding so tails can reach screen bottom.
    expect(
      tester.getRect(find.byType(Fireworks)),
      tester.getRect(find.byType(Scaffold).first),
    );
    expect(find.text('뚜치가 인형이 되어가는 중이에요!'), findsOneWidget);
    expect(find.text('10월 9일 (금)까지 할머니 댁으로 찾아갈게요'), findsOneWidget);
    final placed = (await orders.fetchOrders()).single;
    expect(placed.product, '뚜치 인형');
    expect(placed.price, 51000);
    expect(placed.status, ProfileOrderStatus.preparing);
    expect(placed.options, contains('선물 포장'));
    expect(placed.shipping!.recipient, '김순자');
    expect(find.text(placed.id), findsOneWidget);

    await tester.tap(find.text('주문 현황 보기'));
    await tester.pumpAndSettle();
    expect(find.text('전체 주문 내역'), findsOneWidget);
    expect(find.text('뚜치 인형'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the friend step reads like the Figma options panel', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1194, 834);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildBogleTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: OrderScreen(repository: InMemoryCharacterRepository()),
      ),
    );
    await tester.pumpAndSettle();
    // One paper panel: the question and portrait on the left, ① and every
    // friend as an option card on the right, a summary and the button.
    final panel = tester.getRect(
      find.byKey(const ValueKey('order-pick-panel')),
    );
    final preview = tester.getRect(
      find.byKey(const ValueKey('order-friend-preview')),
    );
    final grid = tester.getRect(
      find.byKey(const ValueKey('order-friend-grid')),
    );
    expect(panel.contains(preview.center), isTrue);
    expect(preview.right, lessThan(grid.left));
    expect(find.text('친구 선택'), findsOneWidget);
    expect(find.text('29,000원부터'), findsOneWidget);
    String picked() => tester
        .widget<Text>(find.byKey(const ValueKey('order-picked-name')))
        .data!;
    expect(picked(), '뭉글이');

    await tester.tap(find.bySemanticsLabel('네모린'));
    await tester.pumpAndSettle();
    expect(picked(), '네모린');
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('order-friend-preview')),
        matching: find.text('네모린'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('네모린 인형 만들기'));
    await tester.pumpAndSettle();
    // The options carry on the numbering: ② size, ③ wrapping.
    expect(find.text('사이즈 선택'), findsOneWidget);
    for (final n in ['2', '3']) {
      expect(find.text(n), findsWidgets);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('every friend, 뭉글이 included, is drawn from its own artwork', (
    tester,
  ) async {
    // A stand-in picture rendered outside Flutter once gave 뭉글이 a white
    // halo here. The portraits may hold the friend's own artwork and nothing
    // else.
    tester.view.physicalSize = const Size(1194, 834);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = InMemoryCharacterRepository();
    final friends = await repo.fetchFriends();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildBogleTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: OrderScreen(repository: repo),
      ),
    );
    await tester.pumpAndSettle();

    void onlyItsOwnArt(Finder portrait, CharacterFriend friend) {
      final art = find.descendant(
        of: portrait,
        matching: find.byType(FriendArtwork),
      );
      expect(art, findsOneWidget, reason: friend.name);
      expect(
        tester.widget<FriendArtwork>(art).assetPath,
        friend.assetPath,
        reason: friend.name,
      );
      for (final e
          in find
              .descendant(of: portrait, matching: find.byType(Image))
              .evaluate()) {
        final image = (e.widget as Image).image;
        expect(
          image is FriendArtImage && image.path == friend.assetPath,
          isTrue,
          reason: '${friend.name}: ${(e.widget as Image).image}',
        );
      }
    }

    for (final friend in friends) {
      await tester.tap(find.byKey(ValueKey('order-friend-${friend.id}')));
      await tester.pumpAndSettle();
      onlyItsOwnArt(find.byKey(const ValueKey('order-friend-preview')), friend);
      await tester.tap(find.text('${friend.name} 인형 만들기'));
      await tester.pumpAndSettle();
      onlyItsOwnArt(find.byKey(const ValueKey('order-doll-preview')), friend);
      await tester.tap(find.byTooltip('뒤로'));
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });
}
