import 'package:bogle_app/src/data/app_services.dart';
import 'package:bogle_app/src/data/character_generation.dart';
import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/data/local_store.dart';
import 'package:bogle_app/src/data/order_repository.dart';
import 'package:bogle_app/src/data/profile_repository.dart';
import 'package:bogle_app/src/data/speech_style.dart';
import 'package:bogle_app/src/screens/house/house_widgets.dart';
import 'package:bogle_app/src/screens/profile_screen.dart';
import 'package:bogle_app/src/screens/setup_friend_screen.dart';
import 'package:bogle_app/src/theme/bogle_theme.dart';
import 'package:bogle_app/src/widgets/bogle_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'sketch_completion_test.dart' as sketch;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(
    () => SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]),
  );
  sketch.main();
  Future<void> capture(WidgetTester tester, String name) async {
    await tester.pumpAndSettle();
    await binding.takeScreenshot(name);
    expect(tester.takeException(), isNull);
  }

  testWidgets('iPad: 프로필·팝업과 8가지 말투 선택을 메모리 저장소로 검증', (tester) async {
    tester.testTextInput.register();
    addTearDown(tester.testTextInput.unregister);
    final store = MemoryStore();
    final repo = InMemoryCharacterRepository();
    final profile = InMemoryProfileRepository(store: store);
    final orders = InMemoryOrderRepository();
    final services = AppServices.local(
      characters: repo,
      profile: profile,
      orders: orders,
    );
    Widget wrap(Widget home) => AppServicesScope(
      services: services,
      child: MaterialApp(
        theme: buildBogleTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: home,
      ),
    );
    await tester.pumpWidget(
      wrap(
        ProfileScreen(
          repository: repo,
          profileRepository: profile,
          orderRepository: orders,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('top-action-알림')));
    await capture(tester, 'notification-settings');
    await tester.tap(find.text('친구 소식'));
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect((await profile.fetchProfile()).friendNotifications, false);
    await tester.tap(find.text('개인 정보 수정'));
    await capture(tester, 'profile-editor-top');
    await tester.enterText(
      find.byKey(const ValueKey('profile-nickname')),
      '별빛',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('profile-bio')));
    await tester.enterText(
      find.byKey(const ValueKey('profile-bio')),
      '그림과 구름 구경을 좋아해요.',
    );
    await tester.ensureVisible(find.widgetWithText(FilterChip, '상상 놀이'));
    await tester.tap(find.widgetWithText(FilterChip, '상상 놀이'));
    await tester.ensureVisible(
      find.byKey(const ValueKey('profile-color-mint')),
    );
    await tester.tap(find.byKey(const ValueKey('profile-color-mint')));
    await capture(tester, 'profile-editor-details');
    await tester.tap(find.text('저장'));
    await capture(tester, 'profile-saved');
    final restored = await InMemoryProfileRepository(
      store: store,
    ).fetchProfile();
    expect(restored.nickname, '별빛');
    expect(restored.bio, '그림과 구름 구경을 좋아해요.');
    expect(restored.interests, ['상상 놀이']);
    expect(restored.profileColor, 'mint');
    await tester.scrollUntilVisible(
      find.text('고객센터'),
      240,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('profile-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('고객센터'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('그림과 프로필은 저장되나요?'));
    await capture(tester, 'help');
    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('이용약관 및 개인정보처리방침'));
    await capture(tester, 'privacy-info');
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();
    expect(find.byType(BogleDialog), findsNothing);
    await tester.tap(find.text('결제 수단 관리'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('결제 수단 추가'));
    await capture(tester, 'payment-editor');
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      wrap(
        SetupFriendScreen(
          repository: repo,
          art: const GeneratedArt(
            assetPath: 'assets/figma/character_friend.svg',
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pumpAndSettle();
    await tester.tap(find.text('글자로 적기'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('setup-answer')), '말랑');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '다음'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('다정한 응원가'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('setup-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('구름 구경하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('setup-next')));
    await tester.pumpAndSettle();
    for (final manner in SpeechManner.values) {
      await tester.tap(find.byKey(ValueKey('speech-manner-${manner.name}')));
      await tester.pumpAndSettle();
      for (final polite in [false, true]) {
        await tester.tap(find.text(polite ? '공손한 말' : '편한 말'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<SpeechBubble>(find.byType(SpeechBubble)).text,
          SpeechProfile(manner, polite: polite).preview(SpeechSample.play),
        );
      }
    }
    await capture(tester, 'speech-eight-combinations');
    await tester.tap(find.text('응원'));
    await capture(tester, 'speech-comfort');
    await tester.tap(find.text('이 말투로 정하기'));
    await tester.pumpAndSettle();
    expect(
      (await repo.fetchFriends()).firstWhere((f) => f.name == '말랑').speechStyle,
      'robot_polite',
    );
    binding.reportData = {
      ...?binding.reportData,
      'profileSavedAndRestored': true,
      'notificationSaved': true,
      'dialogsFit': true,
      'speechCombinations': 8,
      'legacyPreservedByUnitTests': true,
    };
    await tester.pumpWidget(const SizedBox());
  });
}
