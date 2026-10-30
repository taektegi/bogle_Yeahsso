import 'package:bogle_app/src/data/character_generation.dart';
import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/screens/setup_friend_screen.dart';
import 'package:bogle_app/src/theme/bogle_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Keeps "listening" until stopped, so the recording state can be seen.
class ScriptedVoice implements VoiceInput {
  VoidCallback? _done;
  @override
  Future<bool> start(ValueChanged<String> onWords, VoidCallback onDone) async {
    _done = onDone;
    onWords('보글보글');
    return true;
  }

  @override
  Future<void> stop() async {
    _done?.call();
    _done = null;
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  Future<void> shot(WidgetTester tester, String name) async {
    for (var i = 0; i < 140; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await binding.takeScreenshot(name);
  }

  testWidgets('friend setup: questions, voice, and becoming friends', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildBogleTheme(),
        home: SetupFriendScreen(
          art: const GeneratedArt(
            assetPath: 'assets/figma/character_friend.svg',
          ),

          repository: InMemoryCharacterRepository(),
          voice: ScriptedVoice(),
        ),
      ),
    );
    await shot(tester, 'ipad-setup-arrive');
    await tester.pump(const Duration(milliseconds: 1600));
    await shot(tester, 'ipad-setup-name');
    await tester.tap(find.text('말로 알려주기'));
    await shot(tester, 'ipad-setup-voice');
    await tester.tap(find.bySemanticsLabel('그만 듣기'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byTooltip('다음'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('다정한 응원가'));
    await shot(tester, 'ipad-setup-personality');
    await tester.tap(find.text('다음'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('구름 구경하기'));
    await tester.tap(find.text('노래 부르기'));
    await shot(tester, 'ipad-setup-favorites');
    await tester.tap(find.text('다음'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('친구처럼 편하게'));
    await shot(tester, 'ipad-setup-speech');
    await tester.tap(find.text('이 말투로 정하기'));
    await tester.pump(const Duration(seconds: 2));
    await shot(tester, 'ipad-setup-friend');
    await tester.tap(find.byKey(const ValueKey('greeting-box')));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byKey(const ValueKey('greeting-box')));
    await shot(tester, 'ipad-setup-farewell');
    expect(tester.takeException(), isNull);
  });
}
