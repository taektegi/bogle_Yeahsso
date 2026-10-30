import 'dart:async';

import 'package:bogle_app/src/data/character_generation.dart';
import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/screens/loading_screen.dart';
import 'package:bogle_app/src/screens/setup_friend_screen.dart';
import 'package:bogle_app/src/theme/bogle_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const newArt = GeneratedArt(assetPath: 'assets/figma/character_friend.svg');

class _HeldJob implements CharacterGenerationJob {
  final done = Completer<GeneratedArt>();
  @override
  Future<GeneratedArt> get result => done.future;
  @override
  void cancel() {}
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('iPad loading copy reveals without changing the outlined font', (
    tester,
  ) async {
    final job = _HeldJob();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildBogleTheme(),
        home: LoadingScreen(
          repository: InMemoryCharacterRepository(),
          startGeneration: () => job,
        ),
      ),
    );
    for (final stage in ['first', 'letters', 'dots']) {
      for (var i = 0; i < 32; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await binding.takeScreenshot('ipad-loading-copy-$stage');
    }
    await tester.pump(const Duration(seconds: 4));
    expect(find.byKey(const ValueKey('loading-copy-reveal')), findsNothing);
    expect(find.byType(SetupFriendScreen), findsNothing);
    await binding.takeScreenshot('ipad-loading-copy-waiting');
    job.done.complete(newArt);
    await tester.pumpAndSettle();
    expect(find.byType(SetupFriendScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('updated Figma bubble composition on iPad', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildBogleTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: LoadingScreen(
          repository: InMemoryCharacterRepository(),
          startGeneration: _HeldJob.new,
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (var i = 0; i < 8; i++) {
      expect(find.byKey(ValueKey('bubble-$i')), findsOneWidget);
    }
    await binding.takeScreenshot('ipad-loading-new-bubbles');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
