import 'dart:io';

import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/data/motion_service.dart';
import 'package:bogle_app/src/screens/friend_screen.dart';
import 'package:bogle_app/src/theme/bogle_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Needs motion_server/run.sh on this Mac. The simulator reaches it on
/// localhost and can read the sample drawing straight from the checkout.
const _sample =
    '/Users/junsang/Bogle_app_service/motion_server/.vendor/AnimatedDrawings/examples/drawings/garlic.png';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('a friend whose drawing animates waves when petted', (
    tester,
  ) async {
    final repo = InMemoryCharacterRepository();
    final friend = (await repo.fetchFriends()).first;
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildBogleTheme(),
        home: FriendScreen(
          repository: repo,
          friend: friend,
          motion: HttpMotionService(
            'http://127.0.0.1:8000',
            loadDrawing: (_) => File(_sample).readAsBytes(),
          ),
        ),
      ),
    );
    // Rendering is cached on the server; loading the GIFs takes a moment.
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    await tester.tap(find.bySemanticsLabel('뭉글이 쓰다듬기'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const ValueKey('friend-motion-clip')), findsOneWidget);
    await binding.takeScreenshot('ipad-motion-wave');
    for (var i = 1; i <= 3; i++) {
      await tester.pump(const Duration(milliseconds: 300));
      await binding.takeScreenshot('ipad-motion-wave$i');
    }
    await tester.pump(const Duration(seconds: 2));
    expect(find.byKey(const ValueKey('friend-motion-clip')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
