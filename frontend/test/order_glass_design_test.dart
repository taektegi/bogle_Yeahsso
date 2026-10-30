import 'dart:io';
import 'dart:ui' as ui;

import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/data/art_source.dart';
import 'package:bogle_app/src/widgets/bogle_widgets.dart';
import 'package:bogle_app/src/data/order_repository.dart';
import 'package:bogle_app/src/data/starter_friends.dart';
import 'package:bogle_app/src/screens/house/house_widgets.dart';
import 'package:bogle_app/src/screens/order_screen.dart';
import 'package:bogle_app/src/theme/bogle_theme.dart';
import 'package:bogle_app/src/widgets/character_preview_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    for (final (family, path) in [
      ('Yangjin', 'assets/fonts/Yangjin.ttf'),
      ('Pretendard', 'assets/fonts/Pretendard-Regular.otf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
    ]) {
      await (FontLoader(family)..addFont(rootBundle.load(path))).load();
    }
  });
  for (final (id, size, highContrast) in [
    ('mindle', const Size(1366, 1024), false),
    ('mungle', const Size(1366, 1024), false),
    ('ppojik', const Size(1366, 1024), false),
    ('mindle', const Size(744, 600), false),
    ('mindle', const Size(1366, 1024), true),
  ]) {
    testWidgets('주문 글래스 미리보기 $id $size 고대비 $highContrast', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final friend = starterFriends().firstWhere((f) => f.id == id);
      await tester.runAsync(() => artLookOf(friend.assetPath));
      if (isPngArt(friend.assetPath)) {
        await tester.pumpWidget(
          const MaterialApp(home: SizedBox(key: ValueKey('precache'))),
        );
        await tester.runAsync(
          () => precacheImage(
            artImage(friend.assetPath),
            tester.element(find.byKey(const ValueKey('precache'))),
          ),
        );
      }
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildBogleTheme(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(highContrast: highContrast, disableAnimations: true),
              child: child!,
            ),
            home: OrderScreen(
              repository: InMemoryCharacterRepository(friends: [friend]),
              orderRepository: InMemoryOrderRepository(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final glass = find.byType(CharacterPreviewSurface);
      expect(glass, findsOneWidget);

      expect(
        find.descendant(of: glass, matching: find.byType(BackdropFilter)),
        highContrast ? findsNothing : findsOneWidget,
      );
      // Frosting is behind the artwork; the image itself has no image filter.
      expect(
        find.descendant(of: glass, matching: find.byType(ImageFiltered)),
        findsNothing,
      );
      final art = tester.widget<FriendArtwork>(
        find.descendant(of: glass, matching: find.byType(FriendArtwork)),
      );
      expect(art.assetPath, friend.assetPath);
      if (id == 'mindle') {
        final base = CharacterPreviewSurface.backdrop(
          Color(friend.accentHex),
          measuredArtLook(friend.assetPath),
        );
        expect(1.05 / (base.computeLuminance() + .05), greaterThan(1.7));
      }
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('CAPTURE_ORDER_GLASS')) {
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            'artifacts/order-glass/$id-${size.width.toInt()}-$highContrast.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }
}
