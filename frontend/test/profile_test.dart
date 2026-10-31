import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/data/order_repository.dart';
import 'package:bogle_app/src/data/profile_repository.dart';
import 'package:bogle_app/src/models/character_friend.dart';
import 'package:bogle_app/src/screens/friend_screen.dart';
import 'package:bogle_app/src/screens/profile_screen.dart';
import 'package:bogle_app/src/theme/bogle_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sample_orders.dart';
import 'package:bogle_app/src/widgets/bogle_dialog.dart';

class EmptyFriends extends InMemoryCharacterRepository {
  @override
  Future<List<CharacterFriend>> fetchFriends() async => [];
}

class TestProfileRepository extends InMemoryProfileRepository {
  bool failRead = false;
  bool failSave = false;
  @override
  Future<UserProfile> fetchProfile() async {
    if (failRead) throw StateError('offline');
    return super.fetchProfile();
  }

  @override
  Future<UserProfile> saveProfile(UserProfile profile) async {
    if (failSave) throw StateError('offline');
    return super.saveProfile(profile);
  }
}

Future<void> showProfile(
  WidgetTester tester, {
  Size size = const Size(1194, 834),
  double scale = 1,
  CharacterRepository? friends,
  ProfileRepository? profile,
  OrderRepository? orders,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildBogleTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          disableAnimations: true,
        ),
        child: child!,
      ),
      home: ProfileScreen(
        repository: friends ?? InMemoryCharacterRepository(),
        profileRepository: profile ?? InMemoryProfileRepository(),
        orderRepository:
            orders ?? InMemoryOrderRepository(orders: sampleOrders),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String greeting(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('profile-greeting'))).data!;

Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find
        .descendant(
          of: find.byKey(const ValueKey('profile-scroll')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final size in [
    const Size(1024, 768),
    const Size(1133, 744),
    const Size(1194, 834),
    const Size(1366, 1024),
    const Size(744, 600),
  ]) {
    testWidgets('landscape $size lays out every section', (tester) async {
      await showProfile(tester, size: size);
      expect(greeting(tester), '안녕, 그린고블린!');
      expect(find.text('내 친구들'), findsOneWidget);
      await reveal(tester, find.text('배송 현황'));
      await reveal(tester, find.text('이용약관 및 개인정보처리방침'));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('profile edit validates, cancels and saves a friend avatar', (
    tester,
  ) async {
    final repo = InMemoryProfileRepository();
    await showProfile(tester, profile: repo);
    await tester.tap(find.text('개인 정보 수정'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('profile-nickname')),
      '   ',
    );
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(find.text('이름을 입력해 주세요.'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('profile-nickname')),
      '취소할이름',
    );
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect((await repo.fetchProfile()).nickname, '그린고블린');

    await tester.tap(find.text('개인 정보 수정'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('profile-nickname')),
      '  별빛  ',
    );
    await tester.tap(find.bySemanticsLabel('뚜치 프로필 선택'));
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(greeting(tester), '안녕, 별빛!');
    expect((await repo.fetchProfile()).avatar, 'assets/figma/dduchi.png');
  });

  testWidgets('friend tiles have no likes and their whole area opens a house', (
    tester,
  ) async {
    final repo = TestProfileRepository();
    await showProfile(tester, profile: repo);
    expect(find.text('찜한 캐릭터'), findsNothing);

    expect(find.byIcon(Icons.favorite_rounded), findsNothing);
    expect(find.byIcon(Icons.favorite_border_rounded), findsNothing);
    expect(find.byTooltip('뚜치 찜하기'), findsNothing);
    expect(find.byTooltip('뭉글이 찜 해제'), findsNothing);
    final tile = tester.getRect(find.bySemanticsLabel('뚜치 만나기'));
    // The former heart's corner is now part of the visit target. Visiting
    // a friend must not depend on the profile being writable.
    repo.failSave = true;
    await tester.tapAt(Offset(tile.right - 24, tile.top + 24));
    await tester.pumpAndSettle();
    expect(find.byType(FriendScreen), findsOneWidget);
    expect(find.textContaining('찜을 저장하지 못했어요'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile header opens news while settings remain in their menu', (
    tester,
  ) async {
    await showProfile(tester);
    await tester.tap(find.byKey(const ValueKey('top-action-알림')));
    await tester.pumpAndSettle();
    expect(find.text('아직 새로운 소식이 없어요.'), findsOneWidget);
    expect(find.text('받고 싶은 소식을 골라 주세요.'), findsNothing);
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('알림 설정'));
    await tester.tap(find.text('알림 설정'));
    await tester.pumpAndSettle();
    expect(find.text('친구 소식'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('notification settings save from their settings menu', (
    tester,
  ) async {
    final repo = TestProfileRepository();
    await showProfile(tester, profile: repo);
    await reveal(tester, find.text('알림 설정'));
    await tester.tap(find.text('알림 설정'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('친구 소식'));
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect((await repo.fetchProfile()).friendNotifications, isFalse);

    repo.failSave = true;
    await reveal(tester, find.text('알림 설정'));
    await tester.tap(find.text('알림 설정'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('주문·배송 소식'));
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(find.textContaining('설정을 저장하지 못했어요'), findsOneWidget);
    expect((await repo.fetchProfile()).orderNotifications, isTrue);
  });

  testWidgets('orders: latest, previous rows, details and full list', (
    tester,
  ) async {
    await showProfile(tester);
    await reveal(tester, find.text('이전 주문 내역'));
    expect(find.text('뭉글이 인형'), findsOneWidget);
    expect(find.text('배송 정보'), findsOneWidget);
    await tester.tap(find.text('뚜치 인형'));
    await tester.pumpAndSettle();
    expect(find.text('주문 상세'), findsOneWidget);
    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();

    await reveal(tester, find.text('전체 주문 내역 보기'));
    await tester.tap(find.text('전체 주문 내역 보기'));
    await tester.pumpAndSettle();
    final dialog = find.byType(BogleDialog);
    await tester.tap(find.widgetWithText(ChoiceChip, '완료'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: dialog, matching: find.text('뭉글이 인형')),
      findsNothing,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('네모린 인형')),
      findsOneWidget,
    );
  });

  testWidgets('empty data and read failure are recoverable', (tester) async {
    final repo = TestProfileRepository()..failRead = true;
    await showProfile(
      tester,
      friends: EmptyFriends(),
      profile: repo,
      orders: InMemoryOrderRepository(),
    );
    expect(find.text('마이페이지를 불러오지 못했어요'), findsOneWidget);
    repo.failRead = false;
    await tester.tap(find.text('다시 불러오기'));
    await tester.pumpAndSettle();
    expect(find.text('지금까지 0개의 캐릭터를 만들었어요.'), findsOneWidget);
    await reveal(tester, find.text('아직 주문 내역이 없어요'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('large type stays usable while editing with the keyboard', (
    tester,
  ) async {
    await showProfile(tester, size: const Size(1024, 768), scale: 2);
    await reveal(tester, find.text('이용약관 및 개인정보처리방침'));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('계정 관리'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('profile-nickname'));
    await tester.ensureVisible(field);
    await tester.enterText(field, '별빛친구');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(greeting(tester), '안녕, 별빛친구!');
    expect(tester.takeException(), isNull);
  });

  testWidgets('character tile opens the friend', (tester) async {
    await showProfile(tester);
    await tester.tap(find.bySemanticsLabel('뚜치 만나기'));
    await tester.pumpAndSettle();
    expect(find.byType(FriendScreen), findsOneWidget);
  });
}
