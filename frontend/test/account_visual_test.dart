import 'dart:io';
import 'dart:ui' as ui;
import 'package:bogle_app/src/data/app_services.dart';
import 'package:bogle_app/src/data/character_generation.dart';
import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/data/order_repository.dart';
import 'package:bogle_app/src/data/profile_repository.dart';
import 'package:bogle_app/src/data/starter_friends.dart';
import 'package:bogle_app/src/screens/profile_screen.dart';
import 'package:bogle_app/src/screens/house/house_widgets.dart' show artLookOf;
import 'package:bogle_app/src/screens/setup_friend_screen.dart';
import 'package:bogle_app/src/theme/bogle_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 실제 앱 폰트로 렌더링한 시각 검수용 PNG. 저장·AI 호출은 메모리로 격리한다.
void main() {
  testWidgets(
    '보글 팝업·프로필·말투 화면 렌더링 검수',
    (tester) async {
      tester.view.physicalSize = const Size(1194, 834);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(() async {
        for (final (family, file) in [
          ('Yangjin', 'Yangjin.ttf'),
          ('Pretendard', 'Pretendard-Regular.otf'),
        ]) {
          await (FontLoader(
            family,
          )..addFont(rootBundle.load('assets/fonts/$file'))).load();
        }
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      });
      final key = GlobalKey();
      final friends = InMemoryCharacterRepository();
      final profile = InMemoryProfileRepository();
      final orders = InMemoryOrderRepository();
      await tester.runAsync(() async {
        for (final friend in starterFriends()) {
          await artLookOf(friend.assetPath);
        }
      });
      final services = AppServices.local(
        characters: friends,
        profile: profile,
        orders: orders,
      );
      Widget wrap(Widget home) => RepaintBoundary(
        key: key,
        child: AppServicesScope(
          services: services,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildBogleTheme(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            ),
            home: home,
          ),
        ),
      );
      Future<void> capture(String name) async {
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final image =
              await (key.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final folder = Directory('artifacts/account-visual')
            ..createSync(recursive: true);
          await File(
            '${folder.path}/$name.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await tester.pumpWidget(
        wrap(
          ProfileScreen(
            repository: friends,
            profileRepository: profile,
            orderRepository: orders,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        for (final friend in starterFriends()) {
          if (friend.assetPath.endsWith('.png')) {
            await precacheImage(
              AssetImage(friend.assetPath),
              tester.element(find.byType(ProfileScreen)),
            );
          }
        }
      });
      await tester.tap(find.byKey(const ValueKey('top-action-알림')));
      await capture('notifications');
      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('개인 정보 수정'));
      await capture('profile-editor');
      await tester.ensureVisible(find.byKey(const ValueKey('profile-bio')));
      await tester.enterText(
        find.byKey(const ValueKey('profile-bio')),
        '그림과 구름 구경을 좋아해요.',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('profile-color-mint')),
      );
      await tester.tap(find.widgetWithText(FilterChip, '상상 놀이'));
      await tester.tap(find.byKey(const ValueKey('profile-color-mint')));
      await capture('profile-details');
      await tester.tap(find.text('저장'));
      await capture('profile-saved');
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
      await capture('help');
      await tester.tap(find.text('닫기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('이용약관 및 개인정보처리방침'));
      await capture('privacy');
      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('결제 수단 관리'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('결제 수단 추가'));
      await capture('payment');
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        wrap(
          SetupFriendScreen(
            repository: friends,
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
      await tester.tap(find.byKey(const ValueKey('speech-manner-robot')));
      await capture('speech');
      await tester.tap(find.byKey(const ValueKey('speech-manner-plain')));
      await capture('speech-selected');
      await tester.pumpWidget(const SizedBox());
    },
    skip: !const bool.fromEnvironment('CAPTURE_ACCOUNT_UI'),
  );
}
