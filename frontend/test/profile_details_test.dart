import 'package:bogle_app/src/data/local_store.dart';
import 'package:bogle_app/src/data/profile_repository.dart';
import 'package:bogle_app/src/widgets/bogle_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'profile_test.dart' show showProfile, reveal, greeting;

void main() {
  test('예전 프로필 기본값과 새 항목의 재실행 저장', () async {
    final store = MemoryStore();
    await store.write('profile', {'nickname': '이전친구'});
    final repo = InMemoryProfileRepository(store: store);
    final old = await repo.fetchProfile();
    expect(old.bio, '');
    expect(old.interests, isEmpty);
    expect(old.profileColor, 'blue');
    await repo.saveProfile(
      old.copyWith(bio: '구름이 좋아요.', interests: ['상상 놀이'], profileColor: 'mint'),
    );
    final restored = await InMemoryProfileRepository(
      store: store,
    ).fetchProfile();
    expect(restored.bio, '구름이 좋아요.');
    expect(restored.interests, ['상상 놀이']);
    expect(restored.profileColor, 'mint');
  });

  testWidgets('소개·활동·색상은 취소하면 유지하고 저장하면 화면에 보인다', (tester) async {
    final repo = InMemoryProfileRepository();
    await showProfile(tester, profile: repo);
    Future<void> edit() async {
      await tester.tap(find.text('개인 정보 수정'));
      await tester.pumpAndSettle();
    }

    Future<void> choose(Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    await edit();
    await tester.ensureVisible(find.byKey(const ValueKey('profile-bio')));
    await tester.enterText(
      find.byKey(const ValueKey('profile-bio')),
      '구름이 좋아요.',
    );
    await choose(find.widgetWithText(FilterChip, '그림 그리기'));
    await choose(find.widgetWithText(FilterChip, '사진 찍기'));
    await choose(find.widgetWithText(FilterChip, '상상 놀이'));
    await choose(find.widgetWithText(FilterChip, '친구 돌보기'));
    expect(find.text('좋아하는 활동은 최대 3개까지 고를 수 있어요.'), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect((await repo.fetchProfile()).bio, '');
    await edit();
    await tester.ensureVisible(find.byKey(const ValueKey('profile-bio')));
    await tester.enterText(
      find.byKey(const ValueKey('profile-bio')),
      '구름이 좋아요.',
    );
    await choose(find.widgetWithText(FilterChip, '상상 놀이'));
    await choose(find.byKey(const ValueKey('profile-color-mint')));
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(find.text('구름이 좋아요.'), findsOneWidget);
    expect(find.text('상상 놀이'), findsOneWidget);
    expect((await repo.fetchProfile()).profileColor, 'mint');
    expect(greeting(tester), '안녕, 그린고블린!');
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('작은 iPad 화면과 글자 배율 $scale 에서 하단 팝업이 스크롤된다', (tester) async {
      await showProfile(tester, size: const Size(744, 600), scale: scale);
      await reveal(tester, find.text('고객센터'));
      await tester.tap(find.text('고객센터'));
      await tester.pumpAndSettle();
      expect(find.byType(BogleDialog), findsOneWidget);
      await tester.tap(find.text('닫기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('이용약관 및 개인정보처리방침'));
      await tester.pumpAndSettle();
      expect(find.byType(BogleDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();
    });
  }
}
