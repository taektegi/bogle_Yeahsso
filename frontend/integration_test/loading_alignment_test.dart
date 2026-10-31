import 'dart:async';

import 'package:bogle_app/src/data/character_generation.dart';
import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/screens/loading_screen.dart';
import 'package:bogle_app/src/theme/bogle_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const newArt = GeneratedArt(assetPath: 'assets/figma/character_friend.svg');

class _HeldJob implements CharacterGenerationJob {
  final _done = Completer<GeneratedArt>();
  @override
  Future<GeneratedArt> get result => _done.future;
  @override
  void cancel() {}
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('loading middle dots and centred return control', (tester) async {
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
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 2)),
    );
    await tester.pumpAndSettle();
    final logo = tester.getCenter(
      find.byKey(const ValueKey('wordmark-reveal')),
    );
    expect(tester.getCenter(find.text('그림으로 돌아가기')).dx, closeTo(logo.dx, .01));
    expect(find.text('· '), findsNWidgets(3));
    // Let the simulator compositor present the decoded assets before capture.
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await binding.takeScreenshot('ipad-loading-centred-dots');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
