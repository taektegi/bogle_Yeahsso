import 'package:bogle_app/src/screens/house/house_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('옆 말풍선의 꼬리는 본체 하단과 같은 선에서 끝나고 좌우 대칭이다', () {
    const size = Size(300, 180);
    final right = SpeechBubble.sideOutline(size, tailRight: true);
    final left = SpeechBubble.sideOutline(size);
    expect(right.getBounds(), Offset.zero & size);
    expect(left.getBounds(), Offset.zero & size);
    // The body-to-tail join is continuous, with no protrusion midway up.
    expect(right.contains(const Offset(259, 160)), true);
    expect(right.contains(const Offset(261, 160)), true);
    expect(right.contains(const Offset(280, 100)), false);
    expect(right.contains(const Offset(298, 179)), true);
    for (var y = 5.0; y < 180; y += 10) {
      for (var x = 5.0; x < 300; x += 10) {
        expect(left.contains(Offset(x, y)), right.contains(Offset(300 - x, y)));
      }
    }
  });
}
