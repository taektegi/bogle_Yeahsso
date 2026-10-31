import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/drawing/color_picker.dart';
import 'package:bogle_app/src/screens/create_studio_screen.dart';
import 'package:bogle_app/src/theme/bogle_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('grid, spectrum, RGB, hex, opacity and saved colours work', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Color selected = Colors.black;
    double opacity = 1;
    final saved = <Color>[Colors.black];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildBogleTheme(),
        home: Scaffold(
          body: StudioColorPicker(
            color: selected,
            opacity: opacity,
            saved: saved,
            onChanged: (c, o) {
              selected = c;
              opacity = o;
            },
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('color-cell-6-3')));
    await tester.pump();
    expect(selected, gridColor(6, 3));
    await tester.tap(find.byTooltip('현재 색상 저장'));
    await tester.pump();
    expect(saved.last, selected);
    await tester.tap(find.text('스펙트럼'));
    await tester.pump();
    final rect = tester.getRect(find.byKey(const ValueKey('color-spectrum')));
    await tester.tapAt(rect.center);
    await tester.pump();
    expect(selected.g, greaterThan(.95));
    expect(selected.b, greaterThan(.95));
    await tester.tap(find.text('슬라이더'));
    await tester.pump();
    await tester.enterText(find.byType(TextFormField), 'FF0088');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(selected, const Color(0xFFFF0088));
    await tester.enterText(find.byType(TextFormField), 'oops');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(selected, const Color(0xFFFF0088));
    expect(find.text('6자리 색상 코드를 입력해 주세요'), findsOneWidget);
    tester
        .widget<Slider>(find.byKey(const ValueKey('color-channel-0')))
        .onChanged!(.5);
    await tester.pump();
    expect(selected.r, closeTo(.5, .01));
    tester
        .widget<Slider>(find.byKey(const ValueKey('color-opacity')))
        .onChanged!(.4);
    await tester.pump();
    expect(opacity, .4);
    expect(find.text('40%'), findsOneWidget);
    expect(
      tester
          .widget<ColoredBox>(find.byKey(const ValueKey('color-preview')))
          .color
          .a,
      closeTo(.4, .01),
    );
    await tester.tap(find.byTooltip('저장 색상 2'));
    await tester.pump();
    expect(selected, gridColor(6, 3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('thickness stays a neutral line and eyedropper adds no ink', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildBogleTheme(),
        home: CreateStudioScreen(repository: InMemoryCharacterRepository()),
      ),
    );
    final canvas = find.byKey(const ValueKey('drawing-canvas'));
    final center = tester.getCenter(canvas);
    await tester.dragFrom(center, const Offset(120, 0));
    await tester.pump();
    await tester.tap(find.byTooltip('색상'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('color-cell-5-3')));
    await tester.pump();
    await tester.tap(find.byTooltip('현재 색상 저장'));
    await tester.tap(find.byTooltip('그림에서 색상 추출'));
    await tester.pumpAndSettle();
    expect(find.text('그림에서 가져올 색상을 눌러 주세요'), findsOneWidget);
    await tester.tapAt(center + const Offset(30, 0));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pumpAndSettle();
    final preview = tester.widget<ColoredBox>(
      find.byKey(const ValueKey('color-preview')),
    );
    expect(preview.color.toARGB32(), BogleColors.ink.toARGB32());
    await tester.tap(find.byTooltip('색상 닫기'));
    await tester.pumpAndSettle();
    final widths = [
      for (var i = 0; i < 3; i++)
        tester.getSize(find.byKey(ValueKey('stroke-width-$i'))),
    ];
    expect(widths[0].width, greaterThan(widths[0].height * 3));
    expect(widths[0].height, lessThan(widths[1].height));
    expect(widths[1].height, lessThan(widths[2].height));
    await tester.tap(find.byTooltip('되돌리기'));
    await tester.pump();
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.undo_rounded),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.byTooltip('색상'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('저장 색상 7'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
