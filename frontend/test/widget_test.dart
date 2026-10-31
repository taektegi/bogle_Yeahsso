import 'package:bogle_app/src/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> waitForStartup(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
  }

  testWidgets('home presents the primary creation journey', (tester) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const BogleApp());
    await waitForStartup(tester);
    // Home illustrations float on a loop, so wait for the entrance only.
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('친구들 보러가기'), findsOneWidget);
    expect(find.text('친구 그리기 / 사진찍기'), findsOneWidget);
    expect(find.text('주문하기'), findsOneWidget);
    expect(find.bySemanticsLabel('친구 그리기 또는 사진찍기'), findsOneWidget);
  });

  testWidgets('home idle motion pauses under pushed screens', (tester) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const BogleApp());
    await waitForStartup(tester);
    await tester.pump(const Duration(seconds: 2));
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.tap(find.text('주문하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('뒤로'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('친구들 보러가기'), findsOneWidget);
  });

  testWidgets('home is static with reduced motion', (tester) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await tester.pumpWidget(const BogleApp());
    await waitForStartup(tester);
    await tester.pumpAndSettle();
    expect(find.text('친구들 보러가기'), findsOneWidget);
  });

  testWidgets('creation studio opens from the primary CTA', (tester) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const BogleApp());
    await waitForStartup(tester);
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.text('친구 그리기 / 사진찍기'));
    await tester.pumpAndSettle();

    // Figma 250:2339: the modes are the top bar's pills.
    expect(find.text('Drawing'), findsOneWidget);
    expect(find.text('Take a photo'), findsOneWidget);
    expect(find.byTooltip('친구로 만들기'), findsOneWidget);
  });
}
