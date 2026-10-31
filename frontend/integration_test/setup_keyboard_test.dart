import 'package:bogle_app/src/data/character_generation.dart';
import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/screens/setup_friend_screen.dart';
import 'package:bogle_app/src/theme/bogle_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('유선 iPad의 실제 키보드 표시와 이름 입력 연결 유지', (tester) async {
    // Do not register TestTextInput: keyboard visibility must come from iOS.
    final repo = InMemoryCharacterRepository();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildBogleTheme(),
        home: SetupFriendScreen(
          repository: repo,
          art: const GeneratedArt(
            assetPath: 'assets/figma/character_friend.svg',
          ),
        ),
      ),
    );
    for (var i = 0; i < 40 && find.text('글자로 적기').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // The choice exists before its entrance animation becomes hittable.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.ensureVisible(find.text('글자로 적기'));
    await tester.tap(find.text('글자로 적기'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    final field = find.byKey(const ValueKey('setup-answer'));
    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    double keyboardHeight() =>
        binding.platformDispatcher.views.first.viewInsets.bottom /
        binding.platformDispatcher.views.first.devicePixelRatio;
    for (var i = 0; i < 80 && keyboardHeight() == 0; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(seconds: 1));
    expect(
      keyboardHeight(),
      greaterThan(100),
      reason: '실제 iOS 소프트웨어 키보드가 표시되어야 함',
    );
    expect(
      tester.state<EditableTextState>(find.byType(EditableText)),
      same(editable),
    );
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
    await binding.takeScreenshot('ipad-native-keyboard-open');
    // Send Korean IME composition to the live field, without mocking the
    // native TextInput channel or reconnecting focus via tester.enterText.
    editable.updateEditingValue(
      const TextEditingValue(
        text: 'ㅂ',
        selection: TextSelection.collapsed(offset: 1),
        composing: TextRange(start: 0, end: 1),
      ),
    );
    await tester.pump(const Duration(milliseconds: 150));
    editable.updateEditingValue(
      const TextEditingValue(
        text: '보글',
        selection: TextSelection.collapsed(offset: 2),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(tester.widget<TextField>(field).controller!.text, '보글');
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
    expect(keyboardHeight(), greaterThan(100));
    await binding.takeScreenshot('ipad-native-keyboard-korean');
    binding.reportData = {
      ...?binding.reportData,
      'nativeKeyboardHeight': keyboardHeight(),
      'sameEditableState': true,
      'koreanCompositionAccepted': true,
      'memoryRepositoryOnly': true,
    };
    expect(tester.takeException(), isNull);
  });
}
