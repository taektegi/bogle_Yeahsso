import 'dart:io';
import 'dart:ui' as ui;

import 'package:bogle_app/src/data/app_services.dart';
import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/data/local_store.dart';
import 'package:bogle_app/src/drawing/studio_draft.dart';
import 'package:bogle_app/src/screens/archive_screen.dart';
import 'package:bogle_app/src/screens/create_studio_screen.dart';
import 'package:bogle_app/src/screens/friend_screen.dart';
import 'package:bogle_app/src/screens/home_screen.dart';
import 'package:bogle_app/src/screens/house/house_widgets.dart';
import 'package:bogle_app/src/screens/order_screen.dart';
import 'package:bogle_app/src/screens/profile_screen.dart';
import 'package:bogle_app/src/theme/bogle_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const tabletViewports = [
  Size(1024, 768),
  Size(1080, 810),
  Size(1133, 744),
  Size(1180, 820),
  Size(1194, 834),
  Size(1210, 834),
  Size(1366, 1024),
  Size(1376, 1032),
  Size(1600, 1200),
  Size(1024, 600),
  Size(744, 600),
  Size(600, 600),
];

void main() {
  const capture = bool.fromEnvironment('CAPTURE_VIEWPORTS');
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final friend in await InMemoryCharacterRepository().fetchFriends()) {
      await artLookOf(friend.assetPath);
      await anchorsFor(friend.assetPath);
    }
    if (capture) {
      for (final (family, path) in [
        ('Yangjin', 'assets/fonts/Yangjin.ttf'),
        ('Pretendard', 'assets/fonts/Pretendard-Regular.otf'),
        ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
      ]) {
        await (FontLoader(family)..addFont(rootBundle.load(path))).load();
      }
    }
  });

  for (final (size, fontScale) in [
    for (final size in tabletViewports) (size, 1.0),
    for (final size in [
      const Size(1366, 1024),
      const Size(1024, 768),
      const Size(744, 600),
      const Size(600, 600),
    ])
      (size, 2.0),
  ]) {
    for (final scene in [
      'home',
      'archive',
      'studio',
      'house',
      'order',
      'profile',
    ]) {
      testWidgets('$scene 자동 화면 적응 $size 글자 $fontScale', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(top: 24, bottom: 20);
        addTearDown(tester.view.reset);
        final repo = InMemoryCharacterRepository();
        final friends = await repo.fetchFriends();
        final services = AppServices.local(characters: repo);
        final draft = StudioDraft(store: MemoryStore());
        await draft.ready;
        final screen = switch (scene) {
          'home' => HomeScreen(repository: repo),
          'archive' => ArchiveScreen(repository: repo),
          'studio' => CreateStudioScreen(repository: repo),
          'house' => FriendScreen(
            repository: repo,
            friend: friends.first,
            clock: () => DateTime(2026, 10, 30, 14),
          ),
          'order' => OrderScreen(repository: repo),
          _ => ProfileScreen(repository: repo),
        };
        final boundary = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: StudioDraftScope(
              draft: draft,
              child: AppServicesScope(
                services: services,
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: buildBogleTheme(),
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      disableAnimations: true,
                      textScaler: TextScaler.linear(fontScale),
                    ),
                    child: child!,
                  ),
                  home: screen,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        expect(tester.takeException(), isNull);
        if (capture &&
            fontScale == 1 &&
            (size == const Size(1366, 1024) ||
                size == const Size(1133, 744) ||
                size == const Size(744, 600))) {
          await tester.runAsync(() async {
            final image =
                await (boundary.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final folder = Directory('artifacts/adaptive-viewports')
              ..createSync(recursive: true);
            const label = String.fromEnvironment(
              'VIEWPORT_CAPTURE_LABEL',
              defaultValue: 'after',
            );
            await File(
              '${folder.path}/$label-$scene-${size.width.toInt()}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox());
        draft.dispose();
      });
    }
  }
}
