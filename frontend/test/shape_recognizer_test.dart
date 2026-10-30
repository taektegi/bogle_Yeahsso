import 'dart:math' as math;

import 'package:bogle_app/src/drawing/shape_recognizer.dart';
import 'package:flutter_test/flutter_test.dart';

List<Offset> polygon(List<Offset> corners, {double noise = 0}) => [
  for (var i = 0; i < corners.length - 1; i++)
    for (var j = 0; j < 20; j++)
      Offset.lerp(corners[i], corners[i + 1], j / 20)! +
          Offset(math.sin(j * 1.7) * noise, math.cos(j * 1.3) * noise),
  corners.last,
];

List<Offset> ellipse(
  double rx,
  double ry, {
  double rotation = 0,
  double turns = 1,
}) => List.generate(121, (i) {
  final t = i / 120 * math.pi * 2 * turns;
  final r = 1 + math.sin(t * 5) * .015;
  final x = rx * math.cos(t) * r, y = ry * math.sin(t) * r;
  return Offset(
    250 + x * math.cos(rotation) - y * math.sin(rotation),
    200 + x * math.sin(rotation) + y * math.cos(rotation),
  );
});

void main() {
  test('a fast stroke with only start and end samples still straightens', () {
    expect(
      ShapeRecognizer.recognize([Offset.zero, const Offset(150, 20)])?.kind,
      SketchShape.line,
    );
  });
  test(
    'slightly shaky lines straighten; curves and scribbles stay freehand',
    () {
      expect(
        ShapeRecognizer.recognize(
          polygon([const Offset(10, 10), const Offset(210, 40)], noise: 2),
        )?.kind,
        SketchShape.line,
      );
      expect(
        ShapeRecognizer.recognize(
          polygon([Offset.zero, const Offset(80, 80), const Offset(160, 0)]),
        ),
        isNull,
      );
      expect(
        ShapeRecognizer.recognize(
          polygon([
            Offset.zero,
            const Offset(100, 0),
            const Offset(0, 10),
            const Offset(100, 20),
            const Offset(0, 30),
          ]),
        ),
        isNull,
      );
      expect(
        ShapeRecognizer.recognize([
          Offset.zero,
          const Offset(1, 1),
          Offset.zero,
        ]),
        isNull,
      );
    },
  );

  test('circle and rotated ellipses recognize independently of direction', () {
    for (final angle in [0.0, .45, 1.2]) {
      for (final radii in [(80.0, 80.0), (130.0, 55.0)]) {
        final points = ellipse(radii.$1, radii.$2, rotation: angle);
        for (final p in [points, points.reversed.toList()]) {
          expect(ShapeRecognizer.recognize(p)?.kind, SketchShape.ellipse);
        }
      }
    }
    expect(ShapeRecognizer.recognize(ellipse(100, 70, turns: 2)), isNull);
    expect(ShapeRecognizer.recognize(ellipse(100, 70, turns: .7)), isNull);
  });

  test('triangles and rectangles including rotated and mid-edge starts', () {
    final shapes = [
      (
        SketchShape.triangle,
        [
          const Offset(20, 180),
          const Offset(100, 20),
          const Offset(210, 180),
          const Offset(20, 180),
        ],
      ),
      (
        SketchShape.rectangle,
        [
          const Offset(30, 30),
          const Offset(230, 30),
          const Offset(230, 170),
          const Offset(30, 170),
          const Offset(30, 30),
        ],
      ),
      (
        SketchShape.rectangle,
        [
          const Offset(130, 30),
          const Offset(230, 30),
          const Offset(230, 170),
          const Offset(30, 170),
          const Offset(30, 30),
          const Offset(130, 30),
        ],
      ),
    ];
    for (final (kind, corners) in shapes) {
      for (final angle in [0.0, .6]) {
        final points = polygon(corners, noise: 1.4)
            .map(
              (p) => Offset(
                p.dx * math.cos(angle) - p.dy * math.sin(angle),
                p.dx * math.sin(angle) + p.dy * math.cos(angle),
              ),
            )
            .toList();
        expect(ShapeRecognizer.recognize(points)?.kind, kind);
      }
    }
  });

  test(
    'recognition is zoom invariant and rejects irregular closed drawings',
    () {
      final points = ellipse(90, 60);
      expect(
        ShapeRecognizer.recognize(
          points.map((p) => p / 4).toList(),
          scale: 4,
        )?.kind,
        SketchShape.ellipse,
      );
      expect(
        ShapeRecognizer.recognize(
          polygon([
            Offset.zero,
            const Offset(100, 20),
            const Offset(30, 60),
            const Offset(100, 160),
            const Offset(0, 120),
            Offset.zero,
          ]),
        ),
        isNull,
      );
    },
  );
}
