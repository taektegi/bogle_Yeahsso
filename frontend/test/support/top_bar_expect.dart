import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Figma 285:3691's shared top bar: wordmark 48 pt in from the left, the
/// three icons 48 pt in from the right (both scaled with the width), all on
/// one line with the page's pill centred on the screen.
void expectTopBar(
  WidgetTester tester, {
  String? pill,
  String logoKey = 'top-bar-logo',
}) {
  final size = tester.view.physicalSize / tester.view.devicePixelRatio;
  final side = 48 * size.width / 1194;
  final logo = tester.getRect(find.byKey(ValueKey(logoKey)));
  final icons = tester.getRect(find.byKey(const ValueKey('top-bar-icons')));
  expect(logo.left, closeTo(side, .5));
  expect(size.width - icons.right, closeTo(side, .5));
  expect(logo.height, closeTo(55, .01));
  expect(icons.center.dy, closeTo(logo.center.dy, .5));
  if (pill != null) {
    final text = tester.getRect(find.text(pill));
    expect(text.center.dx, closeTo(size.width / 2, 1));
    expect(text.center.dy, closeTo(logo.center.dy, 1));
    expect(text.left, greaterThan(logo.right));
    expect(text.right, lessThan(icons.left));
  }
  for (final label in ['홈', '알림', '마이페이지']) {
    final target = tester.getRect(find.byKey(ValueKey('top-action-$label')));
    expect(target.width, greaterThanOrEqualTo(48));
    expect(target.height, greaterThanOrEqualTo(48));
    expect(icons.contains(target.center), isTrue);
  }
}
