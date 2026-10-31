import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bogle_app/src/theme/bogle_theme.dart';
import 'package:bogle_app/src/screens/house/house_widgets.dart';

void main() {
  testWidgets('화면 본문 테마를 적용해도 제목·버튼·짧은 말풍선은 양진체를 유지한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildBogleTheme(),
        home: Builder(
          builder: (context) => withBogleBodyFont(
            context,
            Scaffold(
              body: Column(
                children: [
                  Text(
                    '화면 제목',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const Text('읽는 설명'),
                  FilledButton(onPressed: () {}, child: const Text('주요 버튼')),
                  const TextField(),
                  const SpeechBubble(text: '반가워', boxy: true),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    String? font(String text) => tester
        .renderObject<RenderParagraph>(find.text(text))
        .text
        .style
        ?.fontFamily;
    expect(font('화면 제목'), bogleDisplayFont);
    expect(font('읽는 설명'), bogleBodyFont);
    expect(font('주요 버튼'), bogleDisplayFont);
    expect(font(keepWords('반가워')), bogleDisplayFont);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).style.fontFamily,
      bogleUiFont,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('기본 설정 팝업도 제목과 본문 역할을 구분한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildBogleTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const AlertDialog(
                  title: Text('설정 제목'),
                  content: Text('설정의 긴 설명을 읽어요.'),
                ),
              ),
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    expect(
      tester
          .renderObject<RenderParagraph>(find.text('설정 제목'))
          .text
          .style
          ?.fontFamily,
      bogleDisplayFont,
    );
    expect(
      tester
          .renderObject<RenderParagraph>(find.text('설정의 긴 설명을 읽어요.'))
          .text
          .style
          ?.fontFamily,
      bogleUiFont,
    );
  });
}
